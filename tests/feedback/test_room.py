"""How the reports room tells crash and hang reports (.cursor/skills/redlamp-reports/room.py):
python3 -m unittest discover -s tests/feedback"""

import importlib.util
import json
import pathlib
import unittest

_spec = importlib.util.spec_from_file_location("room", pathlib.Path(__file__).resolve().parents[2] / ".cursor/skills/redlamp-reports/room.py")
room = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(room)


def issue(body="", labels=()):
    return {"body": body, "labels": [{"name": name} for name in labels]}


def line(**fields):
    return f"<!-- redlamp-feedback v1 {json.dumps(fields)} -->\n**Area:** Performance · **Kind:** Bug"


class Incidents(unittest.TestCase):
    def test_the_hidden_line_makes_a_crash_report_a_bug(self):
        filed = issue(line(area="performance", kind="bug", incident="crash", version="0.3.2-alpha (2410)"), ["in-app", "bug"])
        parsed = room.parse_body(filed["body"])
        self.assertEqual((room.kind_of(filed, parsed), room.incident_of(filed, parsed)), ("bug", "crash"))

    def test_the_label_alone_makes_one_too(self):
        filed = issue("Redlamp froze when I opened a folder.", ["hang"])
        parsed = room.parse_body(filed["body"])
        self.assertEqual((room.kind_of(filed, parsed), room.incident_of(filed, parsed)), ("bug", "hang"))

    def test_a_bug_report_names_no_incident(self):
        filed = issue(line(area="masking.sky", kind="bug"), ["in-app", "bug"])
        self.assertIsNone(room.incident_of(filed, room.parse_body(filed["body"])))


class Symbolicated(unittest.TestCase):
    def comment(self, by, body):
        return {"author": {"login": by}, "body": body, "createdAt": "2026-10-14T20:00:00Z",
                "url": "https://github.com/pdcgomes/redlamp/issues/512#issuecomment-1"}

    def test_the_owners_symbolicated_comment_says_where_it_crashed(self):
        hidden = {"version": "0.3.1-alpha", "binary": "RedlampEngine", "culprit": "ImagePipeline.render(_:) (ImagePipeline.swift:212)",
                  "named": 5, "unnamed": 0, "note": None}
        found = room.symbolication(self.comment(room.OWNER, f"<!-- redlamp-symbolicated v1 {json.dumps(hidden)} -->\n**Crash: …**"))
        self.assertEqual((found["binary"], found["culprit"], found["named"]), ("RedlampEngine", hidden["culprit"], 5))

    def test_other_comments_are_not_symbolications(self):
        self.assertIsNone(room.symbolication(self.comment(room.OWNER, "Thanks for reporting this.")))
        self.assertIsNone(room.symbolication(self.comment("someone", '<!-- redlamp-symbolicated v1 {"named": 1} -->')))
