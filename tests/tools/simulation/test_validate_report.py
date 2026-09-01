from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.simulation.validate_report import validate_report


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def valid_report() -> dict:
    return {
        "schema_version": 1,
        "benchmark_id": "combat.headless.v1",
        "captured_at_utc": "2026-09-01T00:00:00Z",
        "simulation_version": 1,
        "content_version": 1,
        "rendering_enabled": False,
        "runtime": {"godot_version": "4.7.2", "platform": "macOS", "processor": "", "model": ""},
        "inputs": {"build_id": "build.fixture", "encounter_id": "encounter.fixture", "root_seed": "42", "duration_ticks": 120, "duration_seconds": 2.0, "command_count": 17},
        "replay": {"state_hash": "a" * 64, "report_hash": "b" * 64, "final_tick": 120},
        "combat": {"damage_dealt": 100.0, "damage_taken": 20.0, "dps": 50.0, "damage_mix": {"damage.lightning": 100.0}, "hits": 4, "critical_hits": 1, "critical_rate": 0.25, "proc_events": 4, "proc_rate": 1.0, "kills": 1, "kills_per_second": 0.5, "events_processed": 8, "max_event_depth": 1},
        "ticks": {"sample_count": 120, "commands_accepted": 17, "tick_time_usec": {"mean": 50.0, "p50": 45, "p95": 70, "p99": 80, "max": 90}, "entity_count": {"min": 2, "mean": 2.0, "peak": 2}},
    }


class SimulationReportValidatorTests(unittest.TestCase):
    def test_valid_report(self) -> None:
        self.assertEqual(validate_report(valid_report()), [])

    def test_unknown_fields_and_invalid_hash_are_rejected(self) -> None:
        report = valid_report()
        report["extra"] = True
        errors = validate_report(report)
        self.assertIn("$.extra is not allowed", errors)

        report = valid_report()
        report["replay"]["state_hash"] = "not-a-hash"
        errors = validate_report(report)
        self.assertIn("$.replay.state_hash must be 64 lowercase hexadecimal characters", errors)

    def test_cross_field_invariants_are_enforced(self) -> None:
        report = valid_report()
        report["replay"]["final_tick"] = 119
        report["combat"]["critical_hits"] = 5
        report["ticks"]["sample_count"] = 119
        errors = validate_report(report)
        self.assertIn("$.replay.final_tick must equal $.inputs.duration_ticks", errors)
        self.assertIn("$.combat.critical_hits must not exceed $.combat.hits", errors)
        self.assertIn("$.ticks.sample_count must equal $.inputs.duration_ticks", errors)

    def test_headless_harness_does_not_wait_for_rendered_frames(self) -> None:
        harness = (
            REPOSITORY_ROOT
            / "project-ashvault/tools/simulation/run_headless.gd"
        ).read_text(encoding="utf-8")

        self.assertNotIn("process_frame", harness)
        self.assertNotIn("physics_frame", harness)
        self.assertNotIn("await ", harness)
        self.assertIn('DisplayServer.get_name() != "headless"', harness)

    def test_report_schema_matches_the_validator_contract(self) -> None:
        schema = json.loads(
            (
                REPOSITORY_ROOT
                / "performance/simulation-report.schema.json"
            ).read_text(encoding="utf-8")
        )

        self.assertEqual(set(schema["required"]), set(valid_report()))
        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)
        self.assertEqual(
            schema["properties"]["benchmark_id"]["const"],
            "combat.headless.v1",
        )
        self.assertFalse(schema["properties"]["rendering_enabled"]["const"])


if __name__ == "__main__":
    unittest.main()
