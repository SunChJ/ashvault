class_name PerformanceMetrics
extends RefCounted

const REPORT_SCHEMA_VERSION := 1

var _tick_durations_usec: Array[int] = []
var _entity_counts: Array[int] = []


func record_tick(duration_usec: int, entity_count: int) -> String:
	if duration_usec < 0:
		return "Tick duration must be non-negative."
	if entity_count < 0:
		return "Entity count must be non-negative."

	_tick_durations_usec.append(duration_usec)
	_entity_counts.append(entity_count)
	return ""


func sample_count() -> int:
	return _tick_durations_usec.size()


func build_report(context: Dictionary, workload: Dictionary) -> Dictionary:
	if _tick_durations_usec.is_empty():
		return {}

	var sorted_durations := _tick_durations_usec.duplicate()
	sorted_durations.sort()
	var sorted_entities := _entity_counts.duplicate()
	sorted_entities.sort()

	return {
		"schema_version": REPORT_SCHEMA_VERSION,
		"benchmark_id": context.get("benchmark_id", ""),
		"captured_at_utc": context.get("captured_at_utc", ""),
		"simulation_version": context.get("simulation_version", 0),
		"rendering_enabled": false,
		"runtime": context.get("runtime", {}).duplicate(true),
		"workload": workload.duplicate(true),
		"sample_count": sample_count(),
		"tick_time_usec": {
			"mean": _mean(_tick_durations_usec),
			"p50": _nearest_rank(sorted_durations, 0.50),
			"p95": _nearest_rank(sorted_durations, 0.95),
			"p99": _nearest_rank(sorted_durations, 0.99),
			"max": sorted_durations[-1],
		},
		"entity_count": {
			"min": sorted_entities[0],
			"mean": _mean(_entity_counts),
			"peak": sorted_entities[-1],
		},
	}


func _nearest_rank(sorted_values: Array[int], percentile: float) -> int:
	var index := ceili(percentile * sorted_values.size()) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]


func _mean(values: Array[int]) -> float:
	var total := 0
	for value in values:
		total += value
	return float(total) / values.size()
