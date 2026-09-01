from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any


HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")
DECIMAL_PATTERN = re.compile(r"^-?(?:0|[1-9][0-9]*)$")
ROOT_FIELDS = {
    "schema_version",
    "benchmark_id",
    "captured_at_utc",
    "simulation_version",
    "content_version",
    "rendering_enabled",
    "runtime",
    "inputs",
    "replay",
    "combat",
    "ticks",
}
RUNTIME_FIELDS = {"godot_version", "platform", "processor", "model"}
INPUT_FIELDS = {
    "build_id",
    "encounter_id",
    "root_seed",
    "duration_ticks",
    "duration_seconds",
    "command_count",
}
REPLAY_FIELDS = {"state_hash", "report_hash", "final_tick"}
COMBAT_FIELDS = {
    "damage_dealt",
    "damage_taken",
    "dps",
    "damage_mix",
    "hits",
    "critical_hits",
    "critical_rate",
    "proc_events",
    "proc_rate",
    "kills",
    "kills_per_second",
    "events_processed",
    "max_event_depth",
}
TICK_FIELDS = {"sample_count", "commands_accepted", "tick_time_usec", "entity_count"}
TIMING_FIELDS = {"mean", "p50", "p95", "p99", "max"}
ENTITY_FIELDS = {"min", "mean", "peak"}


def _exact_object(value: Any, fields: set[str], path: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{path} must be an object"]
    errors = [f"{path}.{name} is required" for name in sorted(fields - value.keys())]
    errors.extend(f"{path}.{name} is not allowed" for name in sorted(value.keys() - fields))
    return errors


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _non_negative_number(value: Any, path: str) -> list[str]:
    if not _is_number(value):
        return [f"{path} must be a number"]
    return [] if value >= 0 else [f"{path} must be non-negative"]


def _non_negative_integer(value: Any, path: str) -> list[str]:
    if not isinstance(value, int) or isinstance(value, bool):
        return [f"{path} must be an integer"]
    return [] if value >= 0 else [f"{path} must be non-negative"]


def validate_report(report: Any) -> list[str]:
    errors = _exact_object(report, ROOT_FIELDS, "$")
    if not isinstance(report, dict):
        return errors

    nested = [
        ("runtime", RUNTIME_FIELDS),
        ("inputs", INPUT_FIELDS),
        ("replay", REPLAY_FIELDS),
        ("combat", COMBAT_FIELDS),
        ("ticks", TICK_FIELDS),
    ]
    for name, fields in nested:
        errors.extend(_exact_object(report.get(name), fields, f"$.{name}"))
    ticks = report.get("ticks")
    if isinstance(ticks, dict):
        errors.extend(_exact_object(ticks.get("tick_time_usec"), TIMING_FIELDS, "$.ticks.tick_time_usec"))
        errors.extend(_exact_object(ticks.get("entity_count"), ENTITY_FIELDS, "$.ticks.entity_count"))
    if errors:
        return errors

    if report["schema_version"] != 1:
        errors.append("$.schema_version must equal 1")
    if report["benchmark_id"] != "combat.headless.v1":
        errors.append("$.benchmark_id must equal combat.headless.v1")
    try:
        datetime.fromisoformat(report["captured_at_utc"].replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        errors.append("$.captured_at_utc must be an ISO 8601 date-time")
    for name in ("simulation_version", "content_version"):
        value = report[name]
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            errors.append(f"$.{name} must be a positive integer")
    if report["rendering_enabled"] is not False:
        errors.append("$.rendering_enabled must be false")

    runtime = report["runtime"]
    for name in ("godot_version", "platform", "processor", "model"):
        if not isinstance(runtime[name], str):
            errors.append(f"$.runtime.{name} must be a string")
    for name in ("godot_version", "platform"):
        if isinstance(runtime[name], str) and not runtime[name]:
            errors.append(f"$.runtime.{name} must not be empty")

    inputs = report["inputs"]
    for name in ("build_id", "encounter_id"):
        if not isinstance(inputs[name], str) or not inputs[name]:
            errors.append(f"$.inputs.{name} must be a non-empty string")
    if not isinstance(inputs["root_seed"], str) or not DECIMAL_PATTERN.fullmatch(inputs["root_seed"]):
        errors.append("$.inputs.root_seed must be a canonical signed decimal string")
    errors.extend(_non_negative_integer(inputs["duration_ticks"], "$.inputs.duration_ticks"))
    if inputs["duration_ticks"] == 0:
        errors.append("$.inputs.duration_ticks must be positive")
    errors.extend(_non_negative_number(inputs["duration_seconds"], "$.inputs.duration_seconds"))
    if _is_number(inputs["duration_seconds"]) and inputs["duration_seconds"] == 0:
        errors.append("$.inputs.duration_seconds must be positive")
    errors.extend(_non_negative_integer(inputs["command_count"], "$.inputs.command_count"))

    replay = report["replay"]
    for name in ("state_hash", "report_hash"):
        if not isinstance(replay[name], str) or not HASH_PATTERN.fullmatch(replay[name]):
            errors.append(f"$.replay.{name} must be 64 lowercase hexadecimal characters")
    errors.extend(_non_negative_integer(replay["final_tick"], "$.replay.final_tick"))
    if replay["final_tick"] != inputs["duration_ticks"]:
        errors.append("$.replay.final_tick must equal $.inputs.duration_ticks")

    combat = report["combat"]
    for name in ("damage_dealt", "damage_taken", "dps", "critical_rate", "proc_rate", "kills_per_second"):
        errors.extend(_non_negative_number(combat[name], f"$.combat.{name}"))
    for name in ("hits", "critical_hits", "proc_events", "kills", "events_processed", "max_event_depth"):
        errors.extend(_non_negative_integer(combat[name], f"$.combat.{name}"))
    if _is_number(combat["critical_rate"]) and combat["critical_rate"] > 1:
        errors.append("$.combat.critical_rate must not exceed one")
    if isinstance(combat["hits"], int) and isinstance(combat["critical_hits"], int) and combat["critical_hits"] > combat["hits"]:
        errors.append("$.combat.critical_hits must not exceed $.combat.hits")
    if not isinstance(combat["damage_mix"], dict):
        errors.append("$.combat.damage_mix must be an object")
    else:
        for damage_type, amount in combat["damage_mix"].items():
            if not isinstance(damage_type, str) or not damage_type:
                errors.append("$.combat.damage_mix keys must be non-empty strings")
            errors.extend(_non_negative_number(amount, f"$.combat.damage_mix.{damage_type}"))

    ticks = report["ticks"]
    errors.extend(_non_negative_integer(ticks["sample_count"], "$.ticks.sample_count"))
    errors.extend(_non_negative_integer(ticks["commands_accepted"], "$.ticks.commands_accepted"))
    if ticks["sample_count"] != inputs["duration_ticks"]:
        errors.append("$.ticks.sample_count must equal $.inputs.duration_ticks")
    timing = ticks["tick_time_usec"]
    for name in TIMING_FIELDS:
        errors.extend(_non_negative_number(timing[name], f"$.ticks.tick_time_usec.{name}"))
    if all(_is_number(timing[name]) for name in TIMING_FIELDS):
        if not timing["p50"] <= timing["p95"] <= timing["p99"] <= timing["max"]:
            errors.append("$.ticks.tick_time_usec must satisfy p50 <= p95 <= p99 <= max")
        if timing["mean"] > timing["max"]:
            errors.append("$.ticks.tick_time_usec.mean must not exceed max")
    entities = ticks["entity_count"]
    for name in ENTITY_FIELDS:
        errors.extend(_non_negative_number(entities[name], f"$.ticks.entity_count.{name}"))
    if all(_is_number(entities[name]) for name in ENTITY_FIELDS):
        if not entities["min"] <= entities["mean"] <= entities["peak"]:
            errors.append("$.ticks.entity_count must satisfy min <= mean <= peak")
    return errors


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate an Ashvault simulation report.")
    parser.add_argument("report", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        report = json.loads(arguments.report.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Unable to read simulation report: {error}")
        return 2
    errors = validate_report(report)
    if errors:
        for error in errors:
            print(error)
        return 1
    print(f"Simulation report is valid: {arguments.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
