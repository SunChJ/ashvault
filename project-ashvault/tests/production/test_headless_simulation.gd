extends SceneTree

const Simulator = preload(
	"res://game/infrastructure/headless/headless_combat_simulation.gd"
)

const BUILD_PATH := "res://tests/fixtures/headless_build.json"
const ENCOUNTER_PATH := "res://tests/fixtures/headless_encounter.json"
const REPLAY_PATH := "res://tests/fixtures/headless_replay.json"
const ROOT_SEED := 424242
const DURATION_TICKS := 120
const EXPECTED_STATE_HASH := "650d204d9ae61efcab7c731456e66db45968ba61f2af16e0b0d3494a24aea6f8"
const EXPECTED_REPORT_HASH := "d8e0ef3d3b1791c45f3d9366f67ac40c49864c76d24008f683b35207319dea64"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator_script: Script = Simulator
	if not simulator_script.can_instantiate():
		push_error("Headless combat simulator failed to compile.")
		quit(1)
		return
	_test_identical_replays_publish_golden_reports()
	_test_changed_command_and_seed_change_state_hash()
	_test_invalid_inputs_and_versions_are_rejected()
	_test_impossible_command_does_not_advance_or_consume_rng()

	if failures.is_empty():
		print("Production headless simulation tests passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_identical_replays_publish_golden_reports() -> void:
	var first := _simulation(_json(REPLAY_PATH), ROOT_SEED)
	var second := _simulation(_json(REPLAY_PATH), ROOT_SEED)
	_run_to_completion(first)
	_run_to_completion(second)
	var first_report: Dictionary = first.deterministic_report()
	var second_report: Dictionary = second.deterministic_report()

	_assert_equal(first_report, second_report, "Identical inputs changed the deterministic report.")
	_assert_equal(first_report["replay"]["state_hash"], EXPECTED_STATE_HASH, "State golden changed.")
	_assert_equal(first_report["replay"]["report_hash"], EXPECTED_REPORT_HASH, "Report golden changed.")
	_assert_equal(first_report["replay"]["final_tick"], DURATION_TICKS, "Replay ended on wrong tick.")
	_assert_equal(first_report["ticks"]["commands_accepted"], 17, "Replay command count changed.")
	_assert_true(first_report["combat"]["hits"] > 0, "Combat replay produced no hits.")
	_assert_true(first_report["combat"]["damage_dealt"] > 0.0, "Combat replay dealt no damage.")
	_assert_true(first_report["combat"]["damage_taken"] > 0.0, "Encounter dealt no damage.")
	_assert_true(first_report["combat"]["events_processed"] > 0, "Combat events were not processed.")
	_assert_equal(first_report["combat"]["max_event_depth"], 1, "Event child depth changed.")
	_assert_true(
		first_report["combat"]["damage_mix"].has("damage.lightning"),
		"Player damage mix lost its authored type."
	)


func _test_changed_command_and_seed_change_state_hash() -> void:
	var baseline := _simulation(_json(REPLAY_PATH), ROOT_SEED)
	_run_to_completion(baseline)
	var changed_replay: Dictionary = _json(REPLAY_PATH)
	changed_replay["batches"][0]["commands"][0]["aim_vector"] = [0.0, 1.0]
	var changed_command := _simulation(changed_replay, ROOT_SEED)
	_run_to_completion(changed_command)
	var changed_seed := _simulation(_json(REPLAY_PATH), ROOT_SEED + 1)
	_run_to_completion(changed_seed)

	_assert_not_equal(
		baseline.state_hash(),
		changed_command.state_hash(),
		"Changing a replay command retained the state hash."
	)
	_assert_not_equal(
		baseline.state_hash(),
		changed_seed.state_hash(),
		"Changing the root seed retained the state hash."
	)


func _test_invalid_inputs_and_versions_are_rejected() -> void:
	var wrong_version := Simulator.new()
	_assert_contains(
		wrong_version.configure(
			_json(BUILD_PATH), _json(ENCOUNTER_PATH), _json(REPLAY_PATH),
			ROOT_SEED, 999, 1, DURATION_TICKS
		),
		"simulation version",
		"Incompatible simulation version was accepted."
	)
	var malformed_build: Dictionary = _json(BUILD_PATH)
	malformed_build.erase("ability")
	var malformed := Simulator.new()
	_assert_contains(
		malformed.configure(
			malformed_build, _json(ENCOUNTER_PATH), _json(REPLAY_PATH),
			ROOT_SEED, 1, 1, DURATION_TICKS
		),
		"ability",
		"Malformed build fixture was accepted."
	)
	var excessive_critical_build: Dictionary = _json(BUILD_PATH)
	excessive_critical_build["ability"]["critical_chance"] = 1.0
	var excessive_critical := Simulator.new()
	_assert_contains(
		excessive_critical.configure(
			excessive_critical_build, _json(ENCOUNTER_PATH), _json(REPLAY_PATH),
			ROOT_SEED, 1, 1, DURATION_TICKS
		),
		"0.95",
		"Critical chance above the production cap was accepted."
	)


func _test_impossible_command_does_not_advance_or_consume_rng() -> void:
	var replay := {
		"schema_version": 1,
		"batches": [{
			"tick": 1,
			"commands": [{
				"tick": 1,
				"actor_id": 1,
				"command_type": "command.cast_release",
				"aim_vector": [1.0, 0.0],
				"ability_slot": 0,
				"client_sequence": 1,
			}],
		}],
	}
	var simulation := _simulation(replay, ROOT_SEED)
	var hash_before: String = simulation.state_hash()
	var error: String = simulation.step()
	_assert_contains(error, "impossible_sequence", "Impossible replay command was accepted.")
	_assert_equal(simulation.tick(), 0, "Rejected replay command advanced simulation.")
	_assert_equal(simulation.state_hash(), hash_before, "Rejected replay consumed deterministic state.")


func _simulation(replay: Dictionary, root_seed: int) -> RefCounted:
	var simulation := Simulator.new()
	var error: String = simulation.configure(
		_json(BUILD_PATH),
		_json(ENCOUNTER_PATH),
		replay,
		root_seed,
		1,
		1,
		DURATION_TICKS
	)
	_assert_equal(error, "", "Headless simulation configuration failed.")
	return simulation


func _run_to_completion(simulation: RefCounted) -> void:
	while not simulation.is_complete():
		var error: String = simulation.step()
		if not error.is_empty():
			failures.append("Headless simulation step failed: %s" % error)
			return


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		failures.append("Fixture '%s' must parse as a Dictionary." % path)
		return {}
	return parsed


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_not_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		failures.append(message)


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])
