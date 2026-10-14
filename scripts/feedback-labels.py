#!/usr/bin/env python3
"""Creates the labels in-app reports carry: `in-app`, `crash` and `hang`, and a `component:` label for each
area in docs/feedback/areas.json (generated from the hierarchy in packages/RedlampUI/Sources/Feedback), and
adds `crash` or `hang` to each open in-app report whose hidden line names an incident.

A dry run by default; --apply makes the changes. Run it after the areas change, and when crash or hang
reports come in. The relay files reports with only the labels that exist, so a report never creates one,
and with none but `in-app`, its kind's and its area's: a report the next launch offers after a crash or a
hang (UX-11) says so in its hidden `<!-- redlamp-feedback v1 {…} -->` line, as "incident": "crash" or
"hang", and gets its label here. Other labels are left alone, and these are outside the namespaces
scripts/tracker-issues.py manages.
"""

import argparse
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Production files into the first; Preview deployments into the second.
REPOS = ("pdcgomes/redlamp", "pdcgomes/redlamp-feedback")
IN_APP = ("in-app", "1d76db", "Filed from Redlamp's Report a Bug or Send Feedback")
INCIDENTS = (
    ("crash", "b60205", "Redlamp quit unexpectedly, and the next launch offered this report"),
    ("hang", "d93f0b", "Redlamp stopped responding, and the next launch offered this report"),
)
COMPONENT_COLOUR = "f9d0c4"
MARKER = re.compile(r"<!-- redlamp-feedback v1 (\{.*?\}) -->")


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def wanted():
    areas = json.loads((ROOT / "docs/feedback/areas.json").read_text())["areas"]
    return [IN_APP, *INCIDENTS] + [(area["label"], COMPONENT_COLOUR, area["summary"]) for area in areas]


def existing(repo):
    labels = json.loads(gh("label", "list", "-R", repo, "--limit", "500", "--json", "name,color,description"))
    return {label["name"]: label for label in labels}


def incident(body):
    """The incident a report's hidden line names, "crash" or "hang", or None."""
    match = MARKER.search(body or "")
    try:
        named = json.loads(match[1]).get("incident") if match else None
    except json.JSONDecodeError:
        return None
    return named if named in {name for name, _, _ in INCIDENTS} else None


def unlabelled(repo):
    """(number, label) for each open in-app report whose hidden line names an incident it isn't labelled with."""
    reports = json.loads(gh("issue", "list", "-R", repo, "--label", "in-app", "--state", "open", "--limit", "1000",
                            "--json", "number,body,labels"))
    out = []
    for report in reports:
        label = incident(report["body"])
        if label and label not in {found["name"] for found in report["labels"]}:
            out.append((report["number"], label))
    return sorted(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--apply", action="store_true", help="make the changes (default: a dry run)")
    parser.add_argument("--repo", action="append", help="only this repository (repeatable)")
    options = parser.parse_args()

    for repo in options.repo or REPOS:
        present = existing(repo)
        changes = []
        for name, colour, description in wanted():
            label = present.get(name)
            if label is None:
                changes.append(("create", name, colour, description))
            elif label["color"].lower() != colour or label["description"] != description:
                changes.append(("update", name, colour, description))
        reports = unlabelled(repo)
        print(f"{repo}: {len(changes)} to create or update, {len(wanted()) - len(changes)} unchanged; "
              f"{len(reports)} crash or hang reports to label")
        for action, name, _, _ in changes:
            print(f"  {action:6s} {name}")
        for number, label in reports:
            print(f"  label  #{number} {label}")
        if options.apply:
            for _, name, colour, description in changes:
                gh("label", "create", name, "-R", repo, "--color", colour, "--description", description, "--force")
            for number, label in reports:
                gh("issue", "edit", str(number), "-R", repo, "--add-label", label)
    if not options.apply:
        print("\nDry run: nothing changed. Run with --apply to make the labels and label the reports.")


if __name__ == "__main__":
    main()
