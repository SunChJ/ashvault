from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from tools.performance.validate_kernel_gate import validate_gate, validate_manifest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = REPOSITORY_ROOT / "performance/kernel-gate-v1.json"
REFERENCE_PATH = (
    REPOSITORY_ROOT
    / "performance/baselines/m1-kernel-m1-pro-godot-4.7.2.json"
)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class KernelGateValidationTests(unittest.TestCase):
    def test_repository_gate_and_reference_capture_pass(self) -> None:
        manifest = load_json(MANIFEST_PATH)
        reference = load_json(REFERENCE_PATH)

        self.assertEqual(validate_gate(manifest, reference, reference), [])

    def test_hash_and_portable_timing_regressions_fail(self) -> None:
        manifest = load_json(MANIFEST_PATH)
        reference = load_json(REFERENCE_PATH)
        current = copy.deepcopy(reference)
        current["replay"]["state_hash"] = "a" * 64
        current["ticks"]["tick_time_usec"].update(
            {"p95": 8001, "p99": 8001, "max": 8001}
        )

        errors = validate_gate(manifest, current, reference)

        self.assertTrue(any("replay.state_hash must equal" in error for error in errors))
        self.assertTrue(any("p95 exceeds 8000 usec" in error for error in errors))

    def test_reference_identity_and_path_are_strict(self) -> None:
        manifest = load_json(MANIFEST_PATH)
        reference = load_json(REFERENCE_PATH)
        changed_reference = copy.deepcopy(reference)
        changed_reference["runtime"]["processor"] = "Different CPU"

        errors = validate_gate(manifest, reference, changed_reference)
        self.assertTrue(any("runtime.processor must equal" in error for error in errors))

        invalid_manifest = copy.deepcopy(manifest)
        invalid_manifest["reference_capture"]["report_path"] = "../outside.json"
        self.assertIn(
            "$.reference_capture.report_path must stay within the repository",
            validate_manifest(invalid_manifest),
        )

    def test_gate_schema_matches_the_manifest_contract(self) -> None:
        schema = load_json(REPOSITORY_ROOT / "performance/kernel-gate.schema.json")
        manifest = load_json(MANIFEST_PATH)

        self.assertEqual(set(schema["required"]), set(manifest))
        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)
        self.assertEqual(schema["properties"]["gate_id"]["const"], "m1.kernel.v1")


if __name__ == "__main__":
    unittest.main()
