extends SceneTree

const Simulation = preload("res://game/infrastructure/headless/build_simulation.gd")
const Gate = preload("res://game/infrastructure/headless/rarity_value_gate.gd")
const Candidates = preload("res://tests/fixtures/builds/reference_candidates.gd")
const PROFILES := ["arc_bolt", "chain_lightning", "nova_ward", "storm_totem"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output" or args[1].is_empty():
		push_error("Usage: --headless --script res://tools/simulation/run_reference_builds.gd -- --output <report.json>")
		quit(2)
		return
	var fixture := Candidates.create()
	var reports: Array = []
	for profile: String in PROFILES:
		var build: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/builds/%s.json" % profile))
		var result := Simulation.compare(build, fixture.world, fixture.bonuses)
		if not result.error.is_empty():
			push_error(result.error)
			quit(3)
			return
		reports.append(result.report)
	var gate := Gate.evaluate(reports)
	var directory_error := DirAccess.make_dir_recursive_absolute(args[1].get_base_dir())
	if directory_error != OK:
		push_error("Cannot create Build report directory: %s" % directory_error)
		quit(4)
		return
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if output == null:
		push_error("Cannot open Build report output: %s" % FileAccess.get_open_error())
		quit(4)
		return
	output.store_string(JSON.stringify({"schema_version": 1, "reports": reports, "gate": gate}, "\t", true, true) + "\n")
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK:
		push_error("Cannot write Build report output.")
		quit(4)
		return
	print(JSON.stringify(gate))
	quit(0 if gate.passed else 1)
