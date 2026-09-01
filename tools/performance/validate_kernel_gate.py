from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from tools.simulation.validate_report import validate_report as validate_simulation_report


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ROOT_FIELDS = {
    "schema_version",
    "gate_id",
    "runtime",
    "replay",
    "thresholds",
    "reference_capture",
}
RUNTIME_FIELDS = {
    "godot_version",
    "simulation_version",
    "content_version",
    "fixed_ticks_per_second",
}
REPLAY_FIELDS = {
    "benchmark_id",
    "build_id",
    "encounter_id",
    "root_seed",
    "duration_ticks",
    "command_count",
    "expected_state_hash",
    "expected_report_hash",
}
THRESHOLD_FIELDS = {
    "portable_tick_p95_usec",
    "apple_m1_pro_tick_p95_usec",
    "max_event_depth",
    "peak_entity_count",
}
REFERENCE_FIELDS = {
    "profile_id",
    "report_path",
    "platform",
    "processor",
    "model",
}
DECIMAL_PATTERN = re.compile(r"^-?(?:0|[1-9][0-9]*)$")


def _exact_object(value: Any, fields: set[str], path: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{path} must be an object"]
    errors = [f"{path}.{name} is required" for name in sorted(fields - value.keys())]
    errors.extend(f"{path}.{name} is not allowed" for name in sorted(value.keys() - fields))
    return errors


def _positive_integer(value: Any, path: str, *, allow_zero: bool = False) -> list[str]:
    if not isinstance(value, int) or isinstance(value, bool):
        return [f"{path} must be an integer"]
    minimum = 0 if allow_zero else 1
    return [] if value >= minimum else [f"{path} must be at least {minimum}"]


def validate_manifest(manifest: Any) -> list[str]:
    errors = _exact_object(manifest, ROOT_FIELDS, "$")
    if not isinstance(manifest, dict):
        return errors
    nested = [
        ("runtime", RUNTIME_FIELDS),
        ("replay", REPLAY_FIELDS),
        ("thresholds", THRESHOLD_FIELDS),
        ("reference_capture", REFERENCE_FIELDS),
    ]
    for name, fields in nested:
        errors.extend(_exact_object(manifest.get(name), fields, f"$.{name}"))
    if errors:
        return errors

    if manifest["schema_version"] != 1:
        errors.append("$.schema_version must equal 1")
    if manifest["gate_id"] != "m1.kernel.v1":
        errors.append("$.gate_id must equal m1.kernel.v1")

    runtime = manifest["runtime"]
    if runtime["godot_version"] != "4.7.2":
        errors.append("$.runtime.godot_version must equal 4.7.2")
    for name in ("simulation_version", "content_version", "fixed_ticks_per_second"):
        errors.extend(_positive_integer(runtime[name], f"$.runtime.{name}"))
    if runtime["fixed_ticks_per_second"] != 60:
        errors.append("$.runtime.fixed_ticks_per_second must equal 60")

    replay = manifest["replay"]
    for name in ("benchmark_id", "build_id", "encounter_id", "root_seed"):
        if not isinstance(replay[name], str) or not replay[name]:
            errors.append(f"$.replay.{name} must be a non-empty string")
    if replay["benchmark_id"] != "combat.headless.v1":
        errors.append("$.replay.benchmark_id must equal combat.headless.v1")
    if (
        isinstance(replay["root_seed"], str)
        and not DECIMAL_PATTERN.fullmatch(replay["root_seed"])
    ):
        errors.append("$.replay.root_seed must be a canonical signed decimal string")
    for name in ("expected_state_hash", "expected_report_hash"):
        value = replay[name]
        if (
            not isinstance(value, str)
            or len(value) != 64
            or any(character not in "0123456789abcdef" for character in value)
        ):
            errors.append(f"$.replay.{name} must be a lowercase SHA-256 hash")
    errors.extend(_positive_integer(replay["duration_ticks"], "$.replay.duration_ticks"))
    errors.extend(
        _positive_integer(replay["command_count"], "$.replay.command_count", allow_zero=True)
    )

    thresholds = manifest["thresholds"]
    for name in ("portable_tick_p95_usec", "apple_m1_pro_tick_p95_usec"):
        errors.extend(_positive_integer(thresholds[name], f"$.thresholds.{name}"))
    errors.extend(
        _positive_integer(
            thresholds["max_event_depth"],
            "$.thresholds.max_event_depth",
            allow_zero=True,
        )
    )
    errors.extend(
        _positive_integer(thresholds["peak_entity_count"], "$.thresholds.peak_entity_count")
    )
    if (
        isinstance(thresholds["apple_m1_pro_tick_p95_usec"], int)
        and isinstance(thresholds["portable_tick_p95_usec"], int)
        and thresholds["apple_m1_pro_tick_p95_usec"]
        > thresholds["portable_tick_p95_usec"]
    ):
        errors.append(
            "$.thresholds.apple_m1_pro_tick_p95_usec must not exceed the portable threshold"
        )

    reference = manifest["reference_capture"]
    for name in REFERENCE_FIELDS:
        if not isinstance(reference[name], str) or not reference[name]:
            errors.append(f"$.reference_capture.{name} must be a non-empty string")
    report_path = reference["report_path"]
    if isinstance(report_path, str):
        relative_path = Path(report_path)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            errors.append("$.reference_capture.report_path must stay within the repository")
    expected_reference = {
        "profile_id": "apple.m1_pro.16gb",
        "platform": "macOS",
        "processor": "Apple M1 Pro",
        "model": "MacBookPro18,3",
    }
    for name, expected in expected_reference.items():
        if reference[name] != expected:
            errors.append(f"$.reference_capture.{name} must equal {expected!r}")
    return errors


def _validate_report_against_gate(
    report: Any,
    manifest: dict[str, Any],
    threshold_name: str,
    label: str,
) -> list[str]:
    schema_errors = validate_simulation_report(report)
    if schema_errors:
        return [f"{label}: {error}" for error in schema_errors]
    runtime = manifest["runtime"]
    replay = manifest["replay"]
    thresholds = manifest["thresholds"]
    expected_values = [
        (report["benchmark_id"], replay["benchmark_id"], "benchmark_id"),
        (report["simulation_version"], runtime["simulation_version"], "simulation_version"),
        (report["content_version"], runtime["content_version"], "content_version"),
        (report["inputs"]["build_id"], replay["build_id"], "inputs.build_id"),
        (report["inputs"]["encounter_id"], replay["encounter_id"], "inputs.encounter_id"),
        (report["inputs"]["root_seed"], replay["root_seed"], "inputs.root_seed"),
        (report["inputs"]["duration_ticks"], replay["duration_ticks"], "inputs.duration_ticks"),
        (report["inputs"]["command_count"], replay["command_count"], "inputs.command_count"),
        (report["ticks"]["commands_accepted"], replay["command_count"], "ticks.commands_accepted"),
        (report["replay"]["state_hash"], replay["expected_state_hash"], "replay.state_hash"),
        (report["replay"]["report_hash"], replay["expected_report_hash"], "replay.report_hash"),
        (
            report["ticks"]["entity_count"]["peak"],
            thresholds["peak_entity_count"],
            "ticks.entity_count.peak",
        ),
    ]
    errors: list[str] = []
    for actual, expected, path in expected_values:
        if actual != expected:
            errors.append(f"{label}.{path} must equal {expected!r}; got {actual!r}")
    godot_version = report["runtime"]["godot_version"]
    if not godot_version.startswith(runtime["godot_version"]):
        errors.append(
            f"{label}.runtime.godot_version must start with {runtime['godot_version']!r}"
        )
    expected_seconds = replay["duration_ticks"] / runtime["fixed_ticks_per_second"]
    if report["inputs"]["duration_seconds"] != expected_seconds:
        errors.append(
            f"{label}.inputs.duration_seconds must equal {expected_seconds!r}"
        )
    if report["combat"]["max_event_depth"] > thresholds["max_event_depth"]:
        errors.append(
            f"{label}.combat.max_event_depth exceeds {thresholds['max_event_depth']}"
        )
    p95 = report["ticks"]["tick_time_usec"]["p95"]
    threshold = thresholds[threshold_name]
    if p95 > threshold:
        errors.append(f"{label}.ticks.tick_time_usec.p95 exceeds {threshold} usec; got {p95}")
    return errors


def validate_gate(
    manifest: Any,
    current_report: Any,
    reference_report: Any,
) -> list[str]:
    errors = validate_manifest(manifest)
    if errors:
        return errors
    typed_manifest: dict[str, Any] = manifest
    errors.extend(
        _validate_report_against_gate(
            current_report,
            typed_manifest,
            "portable_tick_p95_usec",
            "current_report",
        )
    )
    errors.extend(
        _validate_report_against_gate(
            reference_report,
            typed_manifest,
            "apple_m1_pro_tick_p95_usec",
            "reference_report",
        )
    )
    if not errors:
        reference = typed_manifest["reference_capture"]
        for name in ("platform", "processor", "model"):
            actual = reference_report["runtime"][name]
            if actual != reference[name]:
                errors.append(
                    f"reference_report.runtime.{name} must equal {reference[name]!r}; got {actual!r}"
                )
    return errors


def _read_json(path: Path, label: str) -> tuple[Any, str]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), ""
    except (OSError, json.JSONDecodeError) as error:
        return None, f"Unable to read {label} '{path}': {error}"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the Ashvault M1 kernel gate.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("report", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest, error = _read_json(arguments.manifest, "kernel gate manifest")
    if error:
        print(error)
        return 2
    manifest_errors = validate_manifest(manifest)
    if manifest_errors:
        for manifest_error in manifest_errors:
            print(manifest_error)
        return 1
    reference_path = REPOSITORY_ROOT / manifest["reference_capture"]["report_path"]
    reference_report, error = _read_json(reference_path, "reference report")
    if error:
        print(error)
        return 2
    current_report, error = _read_json(arguments.report, "current report")
    if error:
        print(error)
        return 2
    errors = validate_gate(manifest, current_report, reference_report)
    if errors:
        for gate_error in errors:
            print(gate_error)
        return 1
    print(
        "M1 kernel gate passed: "
        f"current P95={current_report['ticks']['tick_time_usec']['p95']} usec, "
        f"M1 Pro P95={reference_report['ticks']['tick_time_usec']['p95']} usec"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
