"""The labels in-app reports carry (scripts/feedback-labels.py): python3 -m unittest discover -s tests/feedback"""

import importlib.util
import json
import pathlib
import unittest
from unittest import mock

_spec = importlib.util.spec_from_file_location("feedback_labels", pathlib.Path(__file__).resolve().parents[2] / "scripts/feedback-labels.py")
labels = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(labels)


def body(**line):
    return f"<!-- redlamp-feedback v1 {json.dumps(line)} -->\n**Area:** Performance · **Kind:** Bug"


class Incidents(unittest.TestCase):
    def test_the_hidden_line_names_a_crash_or_a_hang(self):
        self.assertEqual(labels.incident(body(area="performance", kind="bug", incident="crash")), "crash")
        self.assertEqual(labels.incident(body(area="performance", kind="bug", incident="hang")), "hang")

    def test_a_bug_report_and_a_line_that_isnt_json_name_none(self):
        self.assertIsNone(labels.incident(body(area="masking.sky", kind="bug", version="0.3.0-alpha (2352)")))
        self.assertIsNone(labels.incident(body(kind="bug", incident="freeze")))
        self.assertIsNone(labels.incident("<!-- redlamp-feedback v1 {not json} -->"))
        self.assertIsNone(labels.incident(None))

    def test_only_reports_without_their_label_are_labelled(self):
        found = [
            {"number": 12, "body": body(kind="bug", incident="crash"), "labels": [{"name": "in-app"}]},
            {"number": 13, "body": body(kind="bug", incident="hang"), "labels": [{"name": "in-app"}, {"name": "hang"}]},
            {"number": 14, "body": body(kind="bug"), "labels": [{"name": "in-app"}]},
            {"number": 11, "body": body(kind="bug", incident="hang"), "labels": [{"name": "in-app"}, {"name": "crash"}]},
        ]
        with mock.patch.object(labels, "gh", return_value=json.dumps(found)):
            self.assertEqual(labels.unlabelled("pdcgomes/redlamp"), [(11, "hang"), (12, "crash")])

    def test_crash_and_hang_are_made_with_the_others(self):
        made = {name: colour for name, colour, _ in labels.wanted()}
        self.assertEqual((made["crash"], made["hang"], made["in-app"]), ("b60205", "d93f0b", "1d76db"))
        self.assertTrue(all(len(description) <= 100 for _, _, description in labels.wanted()))
