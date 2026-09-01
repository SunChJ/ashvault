from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.performance.validate_report import validate_report


def valid_report() -> dict[str, object]:
    return {
        "schema_version": 1,
        "benchmark_id": "synthetic.fixed_tick.v1",
        "captured_at_utc": "2026-09-01T00:00:00Z",
        "simulation_version": 1,
        "rendering_enabled": False,
        "runtime": {
            "godot_version": "4.7.2.stable.official",
            "platform": "macOS",
            "processor": "Apple M1 Pro",
            "model": "MacBookPro18,3",
        },
        "workload": {
            "warmup_ticks": 120,
            "sample_ticks": 900,
            "actors": 120,
            "projectiles": 500,
        },
        "sample_count": 900,
        "tick_time_usec": {
            "mean": 1200.5,
            "p50": 1100,
            "p95": 1800,
            "p99": 2200,
            "max": 2600,
        },
        "entity_count": {
            "min": 620,
            "mean": 620.0,
            "peak": 620,
        },
    }


class PerformanceReportValidationTests(unittest.TestCase):
    def test_valid_report_passes(self) -> None:
        self.assertEqual(validate_report(valid_report()), [])

    def test_missing_required_field_fails(self) -> None:
        report = valid_report()
        del report["runtime"]

        self.assertIn("$.runtime is required", validate_report(report))

    def test_percentiles_must_be_monotonic(self) -> None:
        report = valid_report()
        report["tick_time_usec"]["p95"] = 900  # type: ignore[index]

        self.assertIn(
            "$.tick_time_usec must satisfy p50 <= p95 <= p99 <= max",
            validate_report(report),
        )

    def test_sample_count_must_match_workload(self) -> None:
        report = valid_report()
        report["sample_count"] = 899

        self.assertIn(
            "$.sample_count must equal $.workload.sample_ticks",
            validate_report(report),
        )

    def test_rendering_must_be_disabled(self) -> None:
        report = valid_report()
        report["rendering_enabled"] = True

        self.assertIn(
            "$.rendering_enabled must be false",
            validate_report(report),
        )

    def test_archived_m1_pro_baseline_passes(self) -> None:
        repository_root = Path(__file__).resolve().parents[3]
        baseline = json.loads(
            (repository_root / "performance/baselines/m1-pro-godot-4.7.2.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(validate_report(baseline), [])

    def test_report_schema_matches_the_validator_contract(self) -> None:
        repository_root = Path(__file__).resolve().parents[3]
        schema = json.loads(
            (repository_root / "performance/performance-report.schema.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(set(schema["required"]), set(valid_report()))
        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)
        self.assertFalse(schema["properties"]["rendering_enabled"]["const"])

    def test_baseline_harness_does_not_wait_for_rendered_frames(self) -> None:
        repository_root = Path(__file__).resolve().parents[3]
        harness = (
            repository_root
            / "project-ashvault/tools/performance/run_baseline.gd"
        ).read_text(encoding="utf-8")

        self.assertNotIn("process_frame", harness)
        self.assertNotIn("physics_frame", harness)
        self.assertNotIn("await ", harness)
        self.assertIn('DisplayServer.get_name() != "headless"', harness)


if __name__ == "__main__":
    unittest.main()
