from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Tuple, Type, Union


ROOT_FIELDS = {
    "schema_version": int,
    "benchmark_id": str,
    "captured_at_utc": str,
    "simulation_version": int,
    "rendering_enabled": bool,
    "runtime": dict,
    "workload": dict,
    "sample_count": int,
    "tick_time_usec": dict,
    "entity_count": dict,
}
RUNTIME_FIELDS = {
    "godot_version": str,
    "platform": str,
    "processor": str,
    "model": str,
}
WORKLOAD_FIELDS = {
    "warmup_ticks": int,
    "sample_ticks": int,
    "actors": int,
    "projectiles": int,
}
TICK_TIME_FIELDS = {
    "mean": (int, float),
    "p50": int,
    "p95": int,
    "p99": int,
    "max": int,
}
ENTITY_COUNT_FIELDS = {
    "min": int,
    "mean": (int, float),
    "peak": int,
}


def _validate_fields(
    value: Any,
    fields: dict[str, Union[Type[Any], Tuple[Type[Any], ...]]],
    path: str,
) -> list[str]:
    if not isinstance(value, dict):
        return [f"{path} must be an object"]

    errors: list[str] = []
    for name in sorted(value.keys() - fields.keys()):
        errors.append(f"{path}.{name} is not allowed")
    for name, expected_type in fields.items():
        field_path = f"{path}.{name}"
        if name not in value:
            errors.append(f"{field_path} is required")
            continue
        field_value = value[name]
        if isinstance(field_value, bool) and expected_type is not bool:
            errors.append(f"{field_path} has an invalid type")
        elif not isinstance(field_value, expected_type):
            errors.append(f"{field_path} has an invalid type")
    return errors


def validate_report(report: Any) -> list[str]:
    errors = _validate_fields(report, ROOT_FIELDS, "$")
    if not isinstance(report, dict):
        return errors

    errors.extend(_validate_fields(report.get("runtime"), RUNTIME_FIELDS, "$.runtime"))
    errors.extend(_validate_fields(report.get("workload"), WORKLOAD_FIELDS, "$.workload"))
    errors.extend(
        _validate_fields(
            report.get("tick_time_usec"),
            TICK_TIME_FIELDS,
            "$.tick_time_usec",
        )
    )
    errors.extend(
        _validate_fields(
            report.get("entity_count"),
            ENTITY_COUNT_FIELDS,
            "$.entity_count",
        )
    )
    if errors:
        return errors

    if report["schema_version"] != 1:
        errors.append("$.schema_version must equal 1")
    if not report["benchmark_id"]:
        errors.append("$.benchmark_id must not be empty")
    try:
        datetime.fromisoformat(report["captured_at_utc"].replace("Z", "+00:00"))
    except ValueError:
        errors.append("$.captured_at_utc must be an ISO 8601 date-time")
    if report["simulation_version"] < 1:
        errors.append("$.simulation_version must be positive")
    if report["rendering_enabled"] is not False:
        errors.append("$.rendering_enabled must be false")
    if report["sample_count"] <= 0:
        errors.append("$.sample_count must be positive")

    workload = report["workload"]
    for name in WORKLOAD_FIELDS:
        if workload[name] < 0:
            errors.append(f"$.workload.{name} must be non-negative")
    if report["sample_count"] != workload["sample_ticks"]:
        errors.append("$.sample_count must equal $.workload.sample_ticks")
    if workload["sample_ticks"] == 0:
        errors.append("$.workload.sample_ticks must be positive")

    runtime = report["runtime"]
    for name in ("godot_version", "platform"):
        if not runtime[name]:
            errors.append(f"$.runtime.{name} must not be empty")

    timing = report["tick_time_usec"]
    for name in TICK_TIME_FIELDS:
        if timing[name] < 0:
            errors.append(f"$.tick_time_usec.{name} must be non-negative")
    if not timing["p50"] <= timing["p95"] <= timing["p99"] <= timing["max"]:
        errors.append("$.tick_time_usec must satisfy p50 <= p95 <= p99 <= max")
    if timing["mean"] > timing["max"]:
        errors.append("$.tick_time_usec.mean must not exceed max")

    entities = report["entity_count"]
    for name in ENTITY_COUNT_FIELDS:
        if entities[name] < 0:
            errors.append(f"$.entity_count.{name} must be non-negative")
    if not entities["min"] <= entities["mean"] <= entities["peak"]:
        errors.append("$.entity_count must satisfy min <= mean <= peak")

    return errors


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate an Ashvault performance report.")
    parser.add_argument("report", type=Path, help="Path to a performance report JSON file.")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        report = json.loads(arguments.report.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Unable to read performance report: {error}")
        return 2

    errors = validate_report(report)
    if errors:
        for error in errors:
            print(error)
        return 1

    print(f"Performance report is valid: {arguments.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
