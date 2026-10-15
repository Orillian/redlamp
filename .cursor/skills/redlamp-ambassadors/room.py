#!/usr/bin/env python3
"""The ambassadors room: applications from the private repository, and replies to them.

    room.py status                         applications, the owner's marks, and what's waiting on whom
    room.py sync                           read the applications with gh and write the room's APPLICATIONS
                                           block, with thumbnails of their photos (cached, never committed)
    room.py draft NUMBER accept|decline [--line TEXT] [--gmail]
                                           print the reply to an application, with TEXT as its personal
                                           line; --gmail also saves it as a Gmail draft through the press
                                           room's outreach token (never sends)

Applications are issues in pdcgomes/redlamp-ambassadors (or $AMBASSADORS_REPO), filed by the site's
relay (web/lib/ambassadors.ts) with their fields in a hidden `<!-- redlamp-ambassador v1 {…} -->`
marker. The owner's marks live in the room's .canvas.data.json, which this only reads.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CANVAS = Path.home() / ".cursor/projects/Users-pedrogomes-src-darkroom/canvases/ws-ambassadors.canvas.tsx"
STATE = CANVAS.with_name(CANVAS.name.replace(".canvas.tsx", ".canvas.data.json"))
REPO = os.environ.get("AMBASSADORS_REPO", "pdcgomes/redlamp-ambassadors")
CACHE = Path.home() / "Library/Caches/redlamp-ambassadors"
OUTREACH = Path.home() / "src/redlamp-outreach"
MARKER = re.compile(r"<!-- redlamp-ambassador v1 (\{.*?\}) -->")
THUMB_EDGE = 360


def gh(*args, raw=False):
    result = subprocess.run(["gh", *args], capture_output=True)
    if result.returncode != 0:
        message = result.stderr.decode().strip()
        if "Could not resolve to a Repository" in message or "Not Found" in message:
            sys.exit(f"{REPO} isn't there, or gh can't see it. The room's Needs you item says how to set it up.")
        sys.exit(f"gh {' '.join(args[:3])} failed: {message}")
    return result.stdout if raw else json.loads(result.stdout or "null")


def marks():
    if not STATE.exists():
        return {}
    return json.loads(STATE.read_text() or "{}")


def write_block(name, value):
    text = CANVAS.read_text()
    block = json.dumps(value, ensure_ascii=False, indent=1)
    new, count = re.subn(
        rf"/\*{name}:BEGIN\*/.*?/\*{name}:END\*/",
        lambda _: f"/*{name}:BEGIN*/ {block} /*{name}:END*/",
        text,
        flags=re.S,
    )
    if count != 1:
        sys.exit(f"{CANVAS.name} has no {name} block")
    CANVAS.write_text(new)


def read_block(name):
    match = re.search(rf"/\*{name}:BEGIN\*/(.*?)/\*{name}:END\*/", CANVAS.read_text(), re.S)
    return json.loads(match.group(1)) if match else []


def repo_path(url):
    """A file's path in the repository, from the address the relay put in the issue."""
    match = re.search(rf"github\.com/{re.escape(REPO)}/blob/[^/]+/(.+)$", url)
    return match.group(1) if match else None


def thumbnail(number, index, url):
    """A small JPEG of a stored photo, as a data URI, made once and kept in the cache."""
    path = repo_path(url)
    if not path:
        return None
    folder = CACHE / str(number)
    folder.mkdir(parents=True, exist_ok=True)
    folder.chmod(0o700)
    original = folder / f"photo-{index + 1}.jpg"
    thumb = folder / f"thumb-{index + 1}.jpg"
    if not thumb.exists():
        if not original.exists():
            original.write_bytes(gh("api", f"repos/{REPO}/contents/{path}", "-H", "Accept: application/vnd.github.raw", raw=True))
        subprocess.run(
            ["sips", "-Z", str(THUMB_EDGE), "-s", "format", "jpeg", "-s", "formatOptions", "70", str(original), "--out", str(thumb)],
            capture_output=True,
            check=True,
        )
    return "data:image/jpeg;base64," + base64.b64encode(thumb.read_bytes()).decode()


def cmd_sync(_args):
    issues = gh("issue", "list", "-R", REPO, "--state", "all", "--limit", "500", "--json", "number,title,body,state,createdAt,url")
    found = []
    for issue in sorted(issues, key=lambda item: item["number"]):
        match = MARKER.search(issue["body"] or "")
        if not match:
            continue
        fields = json.loads(match.group(1))
        change = re.search(r"\*\*What they'd change first in Redlamp:\*\*\n\n(.*?)\n\n\*\*Edited in Redlamp", issue["body"], re.S)
        found.append(
            {
                "number": issue["number"],
                "created": issue["createdAt"],
                "state": issue["state"].lower(),
                "name": fields.get("name", ""),
                "email": fields.get("email", ""),
                "links": fields.get("links", []),
                "shoots": fields.get("shoots", ""),
                "cameras": fields.get("cameras", ""),
                "change": change.group(1).strip() if change else "",
                "url": issue["url"],
                "thumbs": [t for t in (thumbnail(issue["number"], i, url) for i, url in enumerate(fields.get("photos", []))) if t],
            }
        )
    write_block("APPLICATIONS", found)
    print(f"{len(found)} applications written to {CANVAS.name}.")


def cmd_status(_args):
    applications = read_block("APPLICATIONS")
    state = marks()
    triage = state.get("applications") or {}
    outreach = state.get("candidates") or {}
    needs = {k: v for k, v in (state.get("needsYou") or {}).items() if v}
    print(f"Applications in the room: {len(applications)} (as room.py sync last read them)")
    for kind in ("shortlist", "accept", "decline"):
        numbers = [n for n, mark in triage.items() if mark and mark.get("state") == kind]
        if numbers:
            print(f"  {kind}: #{', #'.join(sorted(numbers, key=int))}")
    untriaged = [a["number"] for a in applications if str(a["number"]) not in triage and a["state"] == "open"]
    if untriaged:
        print(f"  waiting for triage: #{', #'.join(map(str, untriaged))}")
    if outreach:
        counts = {}
        for mark in outreach.values():
            if mark:
                counts[mark["state"]] = counts.get(mark["state"], 0) + 1
        print("Candidates marked: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    if needs:
        print("Needs you marks to fold in: " + ", ".join(f"{k} ({v['state']})" for k, v in needs.items()))


REPLIES = {
    "accept": (
        "Redlamp ambassadors: your application",
        "Hi {first},\n\n"
        "Thanks for applying to be a Redlamp ambassador, and for editing in Redlamp to do it. {line}\n\n"
        "I'd like to have you as one of the founding ambassadors. Before that, I'd like a 20-minute call to talk about how "
        "you edit and what you'd want from Redlamp. Could you send me two or three times over the next week that suit you?\n\n"
        "The terms are on redlamp.app/ambassadors, in case you'd like to read them again before we talk.\n\n"
        "Pedro",
    ),
    "decline": (
        "Redlamp ambassadors: your application",
        "Hi {first},\n\n"
        "Thanks for applying to be a Redlamp ambassador, and for trying Redlamp. {line}\n\n"
        "I'm not taking you on as an ambassador this time. There are only ten places in this first group, and I'm keeping "
        "them to a spread of styles and cameras.\n\n"
        "What you'd change first is noted, and you can always send me more from Help › Send Feedback in the app. "
        "I'll delete your application within six months, or sooner if you ask.\n\n"
        "Pedro",
    ),
}


def cmd_draft(args):
    applications = {a["number"]: a for a in read_block("APPLICATIONS")}
    application = applications.get(args.number)
    if not application:
        sys.exit(f"#{args.number} isn't in the room. Run: room.py sync")
    subject, template = REPLIES[args.kind]
    first = application["name"].split()[0] if application["name"].split() else application["name"]
    body = template.format(first=first, line=args.line.strip()).replace(" \n\n", "\n\n")
    print(f"To: {application['email']}\nSubject: {subject}\n\n{body}")
    if not args.gmail:
        return
    token = OUTREACH / "token.json"
    python = OUTREACH / ".venv/bin/python"
    if not token.exists() or not python.exists():
        sys.exit("\nGmail isn't connected: run `~/src/redlamp-outreach/outreach auth` once, then --gmail again.")
    script = (
        "import sys, json; sys.path.insert(0, sys.argv[1]); import outreach as o; "
        "d = json.loads(sys.argv[2]); s = o.session(); "
        "r = o.check(s.post(f'{o.API}/drafts', json={'message': {'raw': o.raw_message([d['to']], 'pdcgomes@gmail.com', d['subject'], d['body'])}})); "
        "print(r['id'])"
    )
    payload = json.dumps({"to": application["email"], "subject": subject, "body": body})
    result = subprocess.run([str(python), "-c", script, str(OUTREACH), payload], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"\nGmail didn't take the draft: {result.stderr.strip() or result.stdout.strip()}")
    print(f"\nSaved as a Gmail draft ({result.stdout.strip()}). Nothing was sent.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status").set_defaults(run=cmd_status)
    sub.add_parser("sync").set_defaults(run=cmd_sync)
    draft = sub.add_parser("draft")
    draft.add_argument("number", type=int)
    draft.add_argument("kind", choices=sorted(REPLIES))
    draft.add_argument("--line", default="", help="the personal line, about their photos")
    draft.add_argument("--gmail", action="store_true", help="also save it as a Gmail draft")
    draft.set_defaults(run=cmd_draft)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
