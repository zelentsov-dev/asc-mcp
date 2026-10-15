import copy
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import apple_spec_drift


class AppleSpecDriftTests(unittest.TestCase):
    def setUp(self):
        self.spec = {
            "info": {"version": "4.5.1"},
            "paths": {"/v1/apps": {"get": {"operationId": "apps_getCollection"}}},
            "components": {"schemas": {"App": {"type": "object"}}},
        }

    def compare(self, latest):
        before = json.dumps(self.spec).encode()
        after = json.dumps(latest).encode()
        return apple_spec_drift.compare_specs(before, self.spec, after, latest)

    def test_identical_document_passes(self):
        self.assertEqual(self.compare(self.spec)["status"], "unchanged")

    def test_same_version_schema_drift_requires_review(self):
        latest = copy.deepcopy(self.spec)
        latest["components"]["schemas"]["App"]["type"] = "array"
        report = self.compare(latest)
        self.assertEqual(report["status"], "review_required")
        self.assertEqual(report["changedOperations"], [])
        self.assertIn("/components/schemas/App/type", report["changedJSONPointers"])

    def test_added_removed_and_changed_operations_are_reported(self):
        latest = copy.deepcopy(self.spec)
        latest["paths"]["/v1/apps"]["get"]["deprecated"] = True
        latest["paths"]["/v1/new"] = {"post": {"operationId": "new_create"}}
        report = self.compare(latest)
        self.assertEqual(report["changedOperations"], ["apps_getCollection"])
        self.assertEqual(report["addedOperations"], ["new_create"])
        del latest["paths"]["/v1/apps"]
        self.assertEqual(self.compare(latest)["removedOperations"], ["apps_getCollection"])

    def test_byte_drift_is_not_silently_accepted(self):
        before = json.dumps(self.spec).encode()
        report = apple_spec_drift.compare_specs(before, self.spec, before + b"\n", self.spec)
        self.assertEqual(report["status"], "review_required")
        self.assertEqual(report["changedJSONPointerCount"], 0)

    def test_archive_has_exactly_one_spec_and_bounded_contents(self):
        scratch = Path(".build/apple-spec-drift-tests")
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            path = Path(directory) / "spec.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("one/openapi.oas.json", json.dumps(self.spec))
                archive.writestr("two/openapi.oas.json", json.dumps(self.spec))
            with self.assertRaises(ValueError):
                apple_spec_drift.read_spec(path, zipped=True)
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("openapi.oas.json", json.dumps(self.spec))
            with mock.patch.object(apple_spec_drift, "MAX_SPEC_BYTES", 16):
                with self.assertRaises(ValueError):
                    apple_spec_drift.read_spec(path, zipped=True)

    def test_duplicate_operation_ids_are_rejected(self):
        latest = copy.deepcopy(self.spec)
        latest["paths"]["/v1/other"] = {"get": {"operationId": "apps_getCollection"}}
        with self.assertRaises(ValueError):
            self.compare(latest)

    def test_pointer_report_is_bounded(self):
        with mock.patch.object(apple_spec_drift, "MAX_CHANGED_POINTERS", 1):
            pointers, count = apple_spec_drift.changed_pointers({"a": 1, "b": 1}, {"a": 2, "b": 2})
        self.assertEqual(pointers, ["/a"])
        self.assertEqual(count, 2)


if __name__ == "__main__":
    unittest.main()
