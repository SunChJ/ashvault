extends SceneTree

const PerformanceMetrics = preload("res://game/infrastructure/performance_metrics.gd")
const VersionInfo = preload("res://game/infrastructure/version_info.gd")

const BENCHMARK_ID := "synthetic.fixed_tick.v1"
const WARMUP_TICKS := 120
const SAMPLE_TICKS := 900
const ACTOR_COUNT := 120
const PROJECTILE_COUNT := 500
const WORLD_LIMIT := 1024.0

var _actor_positions := PackedVector2Array()
var _actor_velocities := PackedVector2Array()
var _projectile_positions := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Performance baselines must run with --headless.")
		quit(2)
		return

	var output_path := _output_path()
	if output_path.is_empty():
		push_error("Missing required --output <path> argument.")
		quit(2)
		return

	_initialize_workload()
	for tick in WARMUP_TICKS:
		_step_workload(tick)

	var metrics := PerformanceMetrics.new()
	for tick in SAMPLE_TICKS:
		var started_at := Time.get_ticks_usec()
		_step_workload(tick + WARMUP_TICKS)
		var duration_usec := Time.get_ticks_usec() - started_at
		var error := metrics.record_tick(duration_usec, ACTOR_COUNT + PROJECTILE_COUNT)
		if not error.is_empty():
			push_error(error)
			quit(3)
			return

	var report := metrics.build_report(_report_context(), {
		"warmup_ticks": WARMUP_TICKS,
		"sample_ticks": SAMPLE_TICKS,
		"actors": ACTOR_COUNT,
		"projectiles": PROJECTILE_COUNT,
	})
	var write_error := _write_report(output_path, report)
	if not write_error.is_empty():
		push_error(write_error)
		quit(4)
		return

	print(
		"Performance baseline written: %s (P50=%d us, P95=%d us, P99=%d us)"
		% [
			output_path,
			report["tick_time_usec"]["p50"],
			report["tick_time_usec"]["p95"],
			report["tick_time_usec"]["p99"],
		]
	)
	quit(0)


func _initialize_workload() -> void:
	_actor_positions.resize(ACTOR_COUNT)
	_actor_velocities.resize(ACTOR_COUNT)
	for index in ACTOR_COUNT:
		_actor_positions[index] = Vector2(index * 7 % 997, index * 13 % 991)
		_actor_velocities[index] = Vector2(
			0.25 + float(index % 7) * 0.05,
			0.20 + float(index % 5) * 0.04
		)

	_projectile_positions.resize(PROJECTILE_COUNT)
	for index in PROJECTILE_COUNT:
		_projectile_positions[index] = Vector2(index * 11 % 1009, index * 17 % 1013)


func _step_workload(tick: int) -> void:
	for index in ACTOR_COUNT:
		var position := _actor_positions[index] + _actor_velocities[index]
		var velocity := _actor_velocities[index]
		if position.x < 0.0 or position.x > WORLD_LIMIT:
			velocity.x = -velocity.x
		if position.y < 0.0 or position.y > WORLD_LIMIT:
			velocity.y = -velocity.y
		_actor_positions[index] = position.clamp(Vector2.ZERO, Vector2.ONE * WORLD_LIMIT)
		_actor_velocities[index] = velocity

	for index in PROJECTILE_COUNT:
		var position := _projectile_positions[index]
		position.x = fmod(position.x + 0.75 + float(tick % 3) * 0.05, WORLD_LIMIT)
		position.y = fmod(position.y + 0.50 + float(index % 4) * 0.03, WORLD_LIMIT)
		_projectile_positions[index] = position


func _report_context() -> Dictionary:
	return {
		"benchmark_id": BENCHMARK_ID,
		"captured_at_utc": Time.get_datetime_string_from_system(true, false) + "Z",
		"simulation_version": VersionInfo.SIMULATION_VERSION,
		"runtime": {
			"godot_version": Engine.get_version_info().get("string", ""),
			"platform": OS.get_name(),
			"processor": OS.get_processor_name(),
			"model": OS.get_model_name(),
		},
	}


func _output_path() -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size() - 1:
		if arguments[index] == "--output":
			return arguments[index + 1]
	return ""


func _write_report(output_path: String, report: Dictionary) -> String:
	var absolute_path := output_path
	if output_path.begins_with("res://") or output_path.begins_with("user://"):
		absolute_path = ProjectSettings.globalize_path(output_path)

	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return "Unable to create report directory '%s': %s" % [
			absolute_path.get_base_dir(),
			error_string(directory_error),
		]

	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return "Unable to open report '%s': %s" % [
			absolute_path,
			error_string(FileAccess.get_open_error()),
		]
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	return ""
