"""Crash and hang reports' symbolication (scripts/symbolicate-report.py): python3 -m unittest discover -s tests/feedback

The check against a release runs once v0.3.1-alpha's dSYMs are cached (scripts/symbolicate-report.py --fetch
0.3.1-alpha, 105 MB): it picks functions in that release's Redlamp and RedlampEngine with nm, makes a report
whose frames point into them, and expects atos to name each one as swift-demangle names its symbol.
"""

import collections
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/symbolicate-report.py"
_spec = importlib.util.spec_from_file_location("symbolicate_report", SCRIPT)
report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(report)

RELEASE = "0.3.1-alpha"
CACHED = report.CACHE / RELEASE
APPLE = {"name": "libsystem_kernel.dylib", "uuid": "9B4D1E0C-2A6F-3C51-8E7D-41F0A2B3C4D5", "base": 0x18C5A0000, "inApp": False}


def crash(binaries, threads, **fields):
    return {"kind": "crash", "time": "2026-10-14T09:08:08Z", "pid": 4242, "version": f"{RELEASE} (2401)",
            "exception": "EXC_BAD_ACCESS (SIGSEGV)", "reasons": [], "binaries": binaries, "threads": threads,
            "sources": ["crashReport"], **fields}


def hidden(markdown):
    """The hidden line's JSON, from a symbolicated report's Markdown."""
    found = re.match(r"<!-- redlamp-symbolicated v1 (\{.*?\}) -->\n", markdown)
    return json.loads(found[1]) if found else None


class Versions(unittest.TestCase):
    def test_a_version_with_its_build_names_its_release(self):
        self.assertEqual(report.release_version("0.3.2-alpha (431)"), "0.3.2-alpha")
        self.assertEqual(report.release_version("0.3.0-alpha (2352, 0a6c964f27c8)"), "0.3.0-alpha")
        self.assertEqual(report.release_version("0.2.9-prealpha"), "0.2.9-prealpha")

    def test_no_version_names_no_release(self):
        self.assertIsNone(report.release_version(None))
        self.assertIsNone(report.release_version("development"))


class Finding(unittest.TestCase):
    def test_the_diagnostics_a_report_links_to_are_read_through_the_contents_api(self):
        url = "https://github.com/pdcgomes/redlamp-feedback/blob/main/reports/2026/10/62fe/diagnostics.json"
        with mock.patch.object(report, "gh", return_value="{}") as gh:
            report.read_linked(url)
        self.assertEqual(gh.call_args.args[-1], "repos/pdcgomes/redlamp-feedback/contents/reports/2026/10/62fe/diagnostics.json?ref=main")

    def test_a_report_without_diagnostics_says_there_are_no_stacks(self):
        issue = json.dumps({"number": 512, "title": "Crash: EXC_BAD_ACCESS", "url": "", "body": "No attachments"})
        with mock.patch.object(report, "gh", return_value=issue), self.assertRaises(SystemExit) as stopped:
            report.load("512", report.REPO)
        self.assertIn("#512 links no diagnostics.json", str(stopped.exception))

    def test_a_bug_reports_diagnostics_hold_no_incident(self):
        self.assertIsNone(report.incident_in({"format": "app.redlamp.feedback-diagnostics", "kind": "bug"}))
        self.assertEqual(report.incident_in({"incident": {"kind": "hang"}}), {"kind": "hang"})


class Lookups(unittest.TestCase):
    def test_callers_are_looked_up_a_byte_before_their_return_address(self):
        frames = [{"binary": 0, "offset": 0x100}, {"binary": 0, "offset": 0x200}, {"binary": 0, "offset": 0}]
        self.assertEqual([offset for _, offset in report.lookups(frames)], [0x100, 0x1FF, 0])


class Unnamed(unittest.TestCase):
    """What can't be named is said plainly, and its frames keep their offsets."""

    def test_a_binary_from_another_build_says_so(self):
        incident = crash([{"name": "RedlampEngine", "uuid": "AAAAAAAA-0000-0000-0000-000000000000", "inApp": True}],
                         [{"crashed": True, "frames": [{"binary": 0, "offset": 0x7020}]}])
        index = {"882E532C-36EA-3628-A52F-00B5E54DB899": {"name": "RedlampEngine", "arch": "arm64", "path": "/nowhere"}}
        names, unmatched = report.symbolicate(incident, index)
        notes = report.notes_on(unmatched, incident, f"Redlamp {RELEASE}'s dSYMs")
        text = report.markdown(incident, names, notes, version=RELEASE)
        self.assertEqual(unmatched, {0: "other build"})
        self.assertIn("The UUID of RedlampEngine matches none of Redlamp 0.3.1-alpha's dSYMs: the report came from "
                      "another build of Redlamp, such as a development build", text)
        self.assertIn("RedlampEngine  + 0x7020", text)
        self.assertEqual(hidden(text)["unnamed"], 1)

    def test_a_release_without_dsyms_says_so(self):
        assets = json.dumps({"assets": [{"name": "Redlamp-0.2.0-prealpha.zip", "size": 1}]})
        with tempfile.TemporaryDirectory() as cache, mock.patch.object(report, "gh", return_value=assets), \
                self.assertRaises(report.Unavailable) as missing:
            report.release_dsyms("0.2.0-prealpha", cache=pathlib.Path(cache))
        self.assertEqual(str(missing.exception), "Redlamp 0.2.0-prealpha's release has no dSYMs-0.2.0-prealpha.zip, "
                                                 "so there are no dSYMs to name Redlamp's frames with.")

    def test_a_version_that_was_never_released_says_so(self):
        with tempfile.TemporaryDirectory() as cache, \
                mock.patch.object(report, "gh", side_effect=report.GitHubError("release not found")), \
                self.assertRaises(report.Unavailable) as missing:
            report.release_dsyms("9.9.9-alpha", cache=pathlib.Path(cache))
        self.assertIn("has no release v9.9.9-alpha", str(missing.exception))
        self.assertIn("such as a development build", str(missing.exception))

    def test_a_hang_only_the_watchdog_saw_has_no_stacks(self):
        incident = {"kind": "hang", "time": "2026-10-14T09:08:08Z", "pid": 1, "duration": 14.2, "endedSession": True,
                    "threads": [], "binaries": [], "sources": ["watchdog"]}
        text = report.markdown(incident, {}, [], version=RELEASE)
        self.assertIn("**Hang: 14 s, then Redlamp was closed**", text)
        self.assertIn("The report holds no stacks: Redlamp's hang watchdog records when a hang began and how long it "
                      "lasted, not where the main thread was", text)
        self.assertTrue(hidden(text)["note"].startswith("The report holds no stacks"))


class Posting(unittest.TestCase):
    """--comment posts the Markdown, or puts it in place of what an earlier run posted."""

    def run_post(self, earlier):
        calls = []

        def gh(*args, stdin=None):
            calls.append((args, stdin))
            if args[:2] == ("api", "user"):
                return "pdcgomes\n"
            if args[:2] == ("api", "--paginate"):
                return earlier
            return json.dumps({"html_url": "https://github.com/pdcgomes/redlamp/issues/512#issuecomment-1"})

        with mock.patch.object(report, "gh", side_effect=gh):
            url, replaced = report.post(512, report.REPO, "the stacks")
        return calls[-1], replaced

    def test_a_first_run_posts_a_comment(self):
        (args, stdin), replaced = self.run_post("")
        self.assertFalse(replaced)
        self.assertEqual(args[:4], ("api", "-X", "POST", "repos/pdcgomes/redlamp/issues/512/comments"))
        self.assertEqual(json.loads(stdin), {"body": "the stacks"})

    def test_a_later_run_replaces_the_comment_it_posted(self):
        (args, stdin), replaced = self.run_post("1234\n")
        self.assertTrue(replaced)
        self.assertEqual(args[:4], ("api", "-X", "PATCH", "repos/pdcgomes/redlamp/issues/comments/1234"))
        self.assertEqual(json.loads(stdin), {"body": "the stacks"})


class Markdown(unittest.TestCase):
    def test_without_all_only_the_crashed_and_main_threads_show(self):
        frames = [{"binary": 0, "offset": 0x10, "symbol": "mach_msg2_trap"}]
        incident = crash([APPLE], [{"queue": "com.apple.main-thread", "crashed": False, "frames": frames},
                                   {"name": "worker", "crashed": False, "frames": frames},
                                   {"queue": "com.redlamp.render", "crashed": True, "frames": frames}])
        text = report.markdown(incident, {}, [], version=RELEASE, number=512)
        self.assertIn("**Thread 2 crashed**: `com.redlamp.render`", text)
        self.assertIn("**Thread 0, the main thread**", text)
        self.assertNotIn("Thread 1", text)
        self.assertIn("1 other thread not shown: `scripts/symbolicate-report.py 512 --all` prints every thread.", text)
        self.assertIn("Thread 1", report.markdown(incident, {}, [], version=RELEASE, everything=True))

    def test_the_hidden_line_stays_one_html_comment(self):
        incident = crash([APPLE], [{"crashed": True, "frames": [{"binary": 0, "offset": 0x10}]}])
        text = report.markdown(incident, {}, ["A note -- with dashes --> and an arrow."], version=RELEASE)
        first = text.splitlines()[0]
        self.assertEqual(first.count("-->"), 1)
        self.assertEqual(hidden(text)["note"], "A note -- with dashes --> and an arrow.")


@unittest.skipUnless((CACHED / report.UUIDS).exists(),
                     f"v{RELEASE}'s dSYMs aren't cached: scripts/symbolicate-report.py --fetch {RELEASE} downloads them")
class Release(unittest.TestCase):
    """Frames pointing at functions nm finds in v0.3.1-alpha's dSYMs, named by atos."""

    @classmethod
    def setUpClass(cls):
        cls.index = report.cached_index(CACHED)
        cls.dwarf = {entry["name"]: (uuid, entry["path"]) for uuid, entry in cls.index.items()}

    def functions(self, name, count):
        """`count` Swift functions spread through a binary, each alone at its address and 32 bytes or more before
        the next symbol: [(offset from its __TEXT segment, the name swift-demangle gives)]."""
        _, path = self.dwarf[name]
        listed = subprocess.run(["nm", "-n", path], capture_output=True, text=True, check=True).stdout.splitlines()
        symbols = [(int(m[1], 16), m[2], m[3]) for line in listed if (m := re.match(r"^([0-9a-f]{16}) (\w) (.+)$", line))]
        starts = sorted({address for address, _, _ in symbols})
        after = dict(zip(starts, starts[1:]))
        shared = {address for address, count in collections.Counter(a for a, _, _ in symbols).items() if count > 1}
        mangled = f"_$s{len(name)}{name}"
        candidates = [(address, symbol) for address, kind, symbol in symbols
                      if kind in "tT" and symbol.startswith(mangled) and symbol.endswith("F")
                      and address not in shared and after.get(address, address) - address >= 32]
        self.assertGreaterEqual(len(candidates), count, f"too few functions in {name}")
        picked = [candidates[i * (len(candidates) - 1) // (count - 1)] for i in range(count)]
        demangled = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(s[1:] for _, s in picked),
                                   capture_output=True, text=True, check=True).stdout.splitlines()
        text = report.text_address(path)
        return [(address - text, function) for (address, _), function in zip(picked, demangled)]

    def incident(self):
        """Redlamp loaded where the report says, RedlampEngine where its dSYM says (the report gives it no
        address), and one of Apple's frames as the Mac named it."""
        app, engine = self.functions("Redlamp", 3), self.functions("RedlampEngine", 2)
        binaries = [{"name": "Redlamp", "uuid": self.dwarf["Redlamp"][0], "base": 0x1048F4000, "inApp": True},
                    {"name": "RedlampEngine", "uuid": self.dwarf["RedlampEngine"][0], "inApp": True}, APPLE]
        threads = [
            {"queue": "com.apple.main-thread", "crashed": False, "frames": [
                {"binary": 2, "offset": 0x1234, "symbol": "mach_msg2_trap"},
                {"binary": 0, "offset": app[0][0] + 8},
                {"binary": 0, "offset": app[1][0] + 8}]},
            {"queue": "com.redlamp.render", "crashed": True, "frames": [
                {"binary": 1, "offset": engine[0][0]},
                {"binary": 1, "offset": engine[1][0] + 8},
                {"binary": 0, "offset": app[2][0] + 8}]},
        ]
        expected = {(0, app[0][0] + 7): app[0][1], (0, app[1][0] + 7): app[1][1], (1, engine[0][0]): engine[0][1],
                    (1, engine[1][0] + 7): engine[1][1], (0, app[2][0] + 7): app[2][1]}
        return crash(binaries, threads), expected

    def test_atos_names_each_frame_as_its_symbol_demangles(self):
        incident, expected = self.incident()
        names, unmatched = report.symbolicate(incident, self.index)
        self.assertEqual(unmatched, {})
        for key, function in expected.items():
            # atos adds the file and line: "AppDelegate.showWelcome() (RedlampApp.swift:212)".
            self.assertTrue(names.get(key, "").startswith(function + " ("), f"{key}: {names.get(key)!r}, not {function!r}")

    def test_the_script_names_them_from_a_diagnostics_json(self):
        incident, expected = self.incident()
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "diagnostics.json"
            path.write_text(json.dumps({"incident": incident, "system": {"appVersion": RELEASE, "configuration": "Release"}}))
            text = subprocess.run([sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True, check=True).stdout
        for function in expected.values():
            self.assertIn(function + " (", text)
        self.assertIn("**Thread 1 crashed**: `com.redlamp.render`", text)
        self.assertIn("mach_msg2_trap", text)
        self.assertEqual((hidden(text)["named"], hidden(text)["unnamed"]), (5, 0))
        self.assertEqual(hidden(text)["binary"], "RedlampEngine")
