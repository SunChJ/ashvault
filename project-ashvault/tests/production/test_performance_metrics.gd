extends SceneTree

const PerformanceMetrics = preload("res://game/infrastructure/performance_metrics.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_report_percentiles_and_entity_counts()
	_test_invalid_samples_are_rejected_atomically()
	_test_empty_metrics_do_not_publish_a_report()

	if failures.is_empty():
		print("Production performance metrics tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_report_percentiles_and_entity_counts() -> void:
	var metrics := PerformanceMetrics.new()
	var durations: Array[int] = [5, 1, 4, 2, 3]
	var entities: Array[int] = [100, 110, 120, 115, 105]
	for index in durations.size():
		_assert_equal(
			metrics.record_tick(durations[index], entities[index]),
			"",
			"Valid samples must be accepted."
		)

	var report := metrics.build_report(_context(), _workload())
	_assert_equal(report.get("schema_version"), 1, "Schema version must be explicit.")
	_assert_equal(report.get("benchmark_id"), "synthetic.fixed_tick.v1", "Benchmark ID must be stable.")
	_assert_equal(report.get("sample_count"), 5, "Every recorded tick must be counted.")
	_assert_equal(report.get("rendering_enabled"), false, "Simulation reports must declare rendering disabled.")
	_assert_equal(report.get("tick_time_usec", {}).get("mean"), 3.0, "Tick mean must be reported.")
	_assert_equal(report.get("tick_time_usec", {}).get("p50"), 3, "P50 must use nearest rank.")
	_assert_equal(report.get("tick_time_usec", {}).get("p95"), 5, "P95 must use nearest rank.")
	_assert_equal(report.get("tick_time_usec", {}).get("p99"), 5, "P99 must use nearest rank.")
	_assert_equal(report.get("tick_time_usec", {}).get("max"), 5, "Maximum tick time must be reported.")
	_assert_equal(report.get("entity_count", {}).get("min"), 100, "Minimum entity count must be reported.")
	_assert_equal(report.get("entity_count", {}).get("mean"), 110.0, "Entity mean must be reported.")
	_assert_equal(report.get("entity_count", {}).get("peak"), 120, "Peak entity count must be reported.")


func _test_invalid_samples_are_rejected_atomically() -> void:
	var metrics := PerformanceMetrics.new()
	_assert_true(
		metrics.record_tick(-1, 100).contains("non-negative"),
		"Negative tick durations must be rejected."
	)
	_assert_true(
		metrics.record_tick(1, -1).contains("non-negative"),
		"Negative entity counts must be rejected."
	)
	_assert_equal(metrics.sample_count(), 0, "Rejected samples must not partially mutate metrics.")


func _test_empty_metrics_do_not_publish_a_report() -> void:
	var metrics := PerformanceMetrics.new()
	_assert_equal(metrics.build_report(_context(), _workload()), {}, "Empty metrics must not publish a report.")


func _context() -> Dictionary:
	return {
		"benchmark_id": "synthetic.fixed_tick.v1",
		"captured_at_utc": "2026-09-01T00:00:00Z",
		"simulation_version": 1,
		"runtime": {
			"godot_version": "4.7.2.stable.official",
			"platform": "macOS",
			"processor": "Apple M1 Pro",
			"model": "MacBookPro18,3",
		},
	}


func _workload() -> Dictionary:
	return {
		"warmup_ticks": 120,
		"sample_ticks": 5,
		"actors": 120,
		"projectiles": 500,
	}


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
