extends SceneTree

const HeadlessCombatSimulation = preload(
	"res://game/infrastructure/headless/headless_combat_simulation.gd"
)
const EntityWorld = preload("res://game/simulation/entities/entity_world.gd")
const PerformanceMetrics = preload("res://game/infrastructure/performance_metrics.gd")

const BENCHMARK_ID := "combat.headless.v1"
const REQUIRED_OPTIONS := [
	"--build",
	"--encounter",
	"--replay",
	"--root-seed",
	"--simulation-version",
	"--content-version",
	"--duration-seconds",
	"--output",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		_fail("Combat simulation must run with --headless.", 2)
		return

	var options_result := _parse_options(OS.get_cmdline_user_args())
	if not options_result["error"].is_empty():
		_fail(options_result["error"], 2)
		return
	var options: Dictionary = options_result["options"]
	var scalar_result := _parse_scalars(options)
	if not scalar_result["error"].is_empty():
		_fail(scalar_result["error"], 2)
		return

	var build_result := _read_json_object(options["--build"])
	if not build_result["error"].is_empty():
		_fail(build_result["error"], 2)
		return
	var encounter_result := _read_json_object(options["--encounter"])
	if not encounter_result["error"].is_empty():
		_fail(encounter_result["error"], 2)
		return
	var replay_result := _read_json_object(options["--replay"])
	if not replay_result["error"].is_empty():
		_fail(replay_result["error"], 2)
		return

	var simulation := HeadlessCombatSimulation.new()
	var configure_error: String = simulation.configure(
		build_result["value"],
		encounter_result["value"],
		replay_result["value"],
		scalar_result["root_seed"],
		scalar_result["simulation_version"],
		scalar_result["content_version"],
		scalar_result["duration_ticks"]
	)
	if not configure_error.is_empty():
		_fail(configure_error, 3)
		return

	var metrics := PerformanceMetrics.new()
	while not simulation.is_complete():
		var started_at := Time.get_ticks_usec()
		var step_error: String = simulation.step()
		var elapsed_usec := Time.get_ticks_usec() - started_at
		if not step_error.is_empty():
			_fail(step_error, 3)
			return
		var metrics_error: String = metrics.record_tick(
			elapsed_usec,
			simulation.entity_count()
		)
		if not metrics_error.is_empty():
			_fail(metrics_error, 3)
			return

	var report := _build_report(
		simulation.deterministic_report(),
		metrics,
		scalar_result["simulation_version"],
		scalar_result["content_version"]
	)
	var write_error := _write_report(options["--output"], report)
	if not write_error.is_empty():
		_fail(write_error, 4)
		return

	print(
		"Headless combat report written: %s (state=%s, report=%s)"
		% [
			options["--output"],
			report["replay"]["state_hash"],
			report["replay"]["report_hash"],
		]
	)
	quit(0)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	if arguments.size() % 2 != 0:
		return {"error": "Every command-line option requires one value."}
	var options: Dictionary = {}
	for index in range(0, arguments.size(), 2):
		var name := arguments[index]
		if not name in REQUIRED_OPTIONS:
			return {"error": "Unknown command-line option '%s'." % name}
		if options.has(name):
			return {"error": "Duplicate command-line option '%s'." % name}
		var value := arguments[index + 1]
		if value.is_empty():
			return {"error": "Command-line option '%s' requires a value." % name}
		options[name] = value
	for name in REQUIRED_OPTIONS:
		if not options.has(name):
			return {"error": "Missing required %s <value> option." % name}
	return {"error": "", "options": options}


func _parse_scalars(options: Dictionary) -> Dictionary:
	var root_seed_result := _parse_canonical_integer(options["--root-seed"], "--root-seed")
	if not root_seed_result["error"].is_empty():
		return root_seed_result
	var simulation_result := _parse_positive_integer(
		options["--simulation-version"],
		"--simulation-version"
	)
	if not simulation_result["error"].is_empty():
		return simulation_result
	var content_result := _parse_positive_integer(
		options["--content-version"],
		"--content-version"
	)
	if not content_result["error"].is_empty():
		return content_result
	var duration_text: String = options["--duration-seconds"]
	if not duration_text.is_valid_float():
		return {"error": "--duration-seconds must be a positive number."}
	var duration_seconds := duration_text.to_float()
	if not is_finite(duration_seconds) or duration_seconds <= 0.0:
		return {"error": "--duration-seconds must be a positive finite number."}
	var duration_ticks := roundi(duration_seconds * EntityWorld.FIXED_TICKS_PER_SECOND)
	if duration_ticks <= 0:
		return {"error": "--duration-seconds must cover at least one fixed simulation tick."}
	return {
		"error": "",
		"root_seed": root_seed_result["value"],
		"simulation_version": simulation_result["value"],
		"content_version": content_result["value"],
		"duration_ticks": duration_ticks,
	}


func _parse_positive_integer(text: String, option: String) -> Dictionary:
	var parsed := _parse_canonical_integer(text, option)
	if not parsed["error"].is_empty():
		return parsed
	if parsed["value"] <= 0:
		return {"error": "%s must be positive." % option}
	return parsed


func _parse_canonical_integer(text: String, option: String) -> Dictionary:
	if not text.is_valid_int():
		return {"error": "%s must be a canonical signed decimal integer." % option}
	var value := text.to_int()
	if str(value) != text:
		return {"error": "%s must be a canonical signed decimal integer." % option}
	return {"error": "", "value": value}


func _read_json_object(path: String) -> Dictionary:
	var absolute_path := _absolute_path(path)
	if not FileAccess.file_exists(absolute_path):
		return {"error": "Input file does not exist: %s" % path}
	var json := JSON.new()
	var error := json.parse(FileAccess.get_file_as_string(absolute_path))
	if error != OK:
		return {
			"error": "Unable to parse JSON '%s' at line %d: %s" % [
				path,
				json.get_error_line(),
				json.get_error_message(),
			],
		}
	if not json.data is Dictionary:
		return {"error": "Input JSON root must be an object: %s" % path}
	return {"error": "", "value": json.data}


func _build_report(
	deterministic: Dictionary,
	metrics: RefCounted,
	simulation_version: int,
	content_version: int
) -> Dictionary:
	var captured_at_utc := Time.get_datetime_string_from_system(true, false) + "Z"
	var observed: Dictionary = metrics.build_report({
		"benchmark_id": BENCHMARK_ID,
		"captured_at_utc": captured_at_utc,
		"simulation_version": simulation_version,
		"runtime": _runtime_identity(),
	}, {})
	var ticks: Dictionary = deterministic["ticks"].duplicate(true)
	ticks["sample_count"] = observed["sample_count"]
	ticks["tick_time_usec"] = observed["tick_time_usec"]
	ticks["entity_count"] = observed["entity_count"]
	return {
		"schema_version": 1,
		"benchmark_id": BENCHMARK_ID,
		"captured_at_utc": captured_at_utc,
		"simulation_version": simulation_version,
		"content_version": content_version,
		"rendering_enabled": false,
		"runtime": observed["runtime"],
		"inputs": deterministic["inputs"],
		"replay": deterministic["replay"],
		"combat": deterministic["combat"],
		"ticks": ticks,
	}


func _runtime_identity() -> Dictionary:
	return {
		"godot_version": Engine.get_version_info().get("string", ""),
		"platform": OS.get_name(),
		"processor": OS.get_processor_name(),
		"model": OS.get_model_name(),
	}


func _write_report(output_path: String, report: Dictionary) -> String:
	var absolute_path := _absolute_path(output_path)
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


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _fail(message: String, exit_code: int) -> void:
	push_error(message)
	quit(exit_code)
