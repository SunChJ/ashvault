extends SceneTree

const EntityState = preload("res://game/simulation/entities/entity_state.gd")
const EntityWorld = preload("res://game/simulation/entities/entity_world.gd")
const PlayerCommand = preload("res://game/simulation/commands/player_command.gd")
const DamageResult = preload("res://game/simulation/combat/damage_result.gd")

const FIXTURE_PATH := "res://tests/fixtures/entity_command_replay.json"
const EXPECTED_FINAL_HASH := "93bc6abe5dda72e9e2ff6e8c634ddba37bb99177030d0703eb752a036d3ca274"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_command_contract_and_dictionary_round_trip()
	_test_fixed_tick_replay_and_rendering_independence()
	_test_rejections_are_atomic()
	_test_cast_sequence_contract()
	_test_presentation_snapshots_are_read_only()
	_test_entity_world_configuration_is_transactional()

	if failures.is_empty():
		print("Production entity command tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_command_contract_and_dictionary_round_trip() -> void:
	var source := {
		"tick": 7,
		"actor_id": 11,
		"command_type": "command.cast_start",
		"aim_vector": [0.0, -1.0],
		"ability_slot": 3,
		"client_sequence": 19,
	}
	var command := PlayerCommand.new()
	_assert_equal(command.configure_from_dictionary(source), "", "Valid command DTO was rejected.")
	source["tick"] = 99
	source["aim_vector"][0] = 1.0
	_assert_equal(command.tick(), 7, "Command retained caller tick storage.")
	_assert_equal(command.aim_vector(), Vector2(0.0, -1.0), "Command retained caller vector storage.")
	_assert_equal(
		command.to_dictionary(),
		{
			"tick": 7,
			"actor_id": 11,
			"command_type": "command.cast_start",
			"aim_vector": [0.0, -1.0],
			"ability_slot": 3,
			"client_sequence": 19,
		},
		"Command DTO round-trip changed its schema."
	)
	_assert_contains(
		command.configure(7, 11, "command.cancel", Vector2.ZERO, -1, 20),
		"immutable",
		"Published commands must reject reconfiguration."
	)

	var unknown := PlayerCommand.new()
	_assert_contains(
		unknown.configure(1, 1, "command.teleport", Vector2.ZERO, -1, 1),
		"Unknown player command",
		"Unknown command types must be rejected."
	)
	var malformed := PlayerCommand.new()
	_assert_contains(
		malformed.configure_from_dictionary({"tick": 1}),
		"exactly",
		"Malformed replay DTOs must be rejected."
	)
	var invalid_vector := PlayerCommand.new()
	_assert_contains(
		invalid_vector.configure(1, 1, "command.aim", Vector2.ZERO, -1, 1),
		"non-zero",
		"Aim commands must reject a zero direction."
	)


func _test_fixed_tick_replay_and_rendering_independence() -> void:
	var fixture: Dictionary = _load_fixture()
	_assert_equal(fixture.get("schema_version"), 1.0, "Replay fixture schema changed.")
	var with_presentation := _world()
	var headless_only := _world()
	var tick_hashes: Array[String] = []
	var released_snapshot: RefCounted = null

	for batch: Dictionary in fixture.get("batches", []):
		var first_commands := _commands_from_batch(batch)
		var second_commands := _commands_from_batch(batch)
		var first_result: RefCounted = with_presentation.advance_tick(first_commands)
		var second_result: RefCounted = headless_only.advance_tick(second_commands)
		_assert_true(first_result.is_success(), "Fixture batch failed in presentation replay.")
		_assert_true(second_result.is_success(), "Fixture batch failed in headless replay.")
		var snapshot: RefCounted = with_presentation.presentation_snapshot()
		if snapshot.tick() == 3:
			released_snapshot = snapshot
		_assert_equal(snapshot.state_hash(), with_presentation.state_hash(), "Snapshot hash diverged.")
		_assert_equal(
			with_presentation.state_hash(),
			headless_only.state_hash(),
			"Publishing snapshots changed authoritative replay state."
		)
		tick_hashes.append(with_presentation.state_hash())

	_assert_equal(with_presentation.tick(), 4, "Replay did not advance exactly four fixed ticks.")
	_assert_equal(tick_hashes.size(), 4, "Replay must publish one hash per accepted tick.")
	_assert_equal(tick_hashes[-1], EXPECTED_FINAL_HASH, "Replay golden hash changed.")
	_assert_true(released_snapshot != null, "Tick-three presentation snapshot was not captured.")
	if released_snapshot != null:
		var player: RefCounted = released_snapshot.entity(1)
		_assert_equal(player.cast_phase(), "cast.released", "Cast release was not exposed for its tick.")
		_assert_equal(player.ability_slot(), 0, "Released cast lost its ability slot.")
	var final_player: RefCounted = with_presentation.presentation_snapshot().entity(1)
	_assert_equal(final_player.cast_phase(), "cast.idle", "Terminal cast phase did not clear next tick.")
	_assert_equal(final_player.movement_input(), Vector2.RIGHT, "Movement intent did not persist.")
	_assert_equal(final_player.aim_direction(), Vector2.DOWN, "Aim intent did not replay.")


func _test_rejections_are_atomic() -> void:
	var world := _world()
	var first: RefCounted = world.advance_tick([
		_command(1, 1, "command.move", Vector2.RIGHT, -1, 1),
	])
	_assert_true(first.is_success(), "Valid first command failed.")
	var hash_before: String = world.state_hash()
	var snapshot_before: RefCounted = world.presentation_snapshot()

	var impossible: RefCounted = world.advance_tick([
		_command(2, 1, "command.aim", Vector2.UP, -1, 2),
		_command(2, 1, "command.cast_release", Vector2.UP, 0, 3),
	])
	_assert_rejected(impossible, "command.impossible_sequence", "Impossible release was accepted.")
	_assert_equal(world.tick(), 1, "Rejected batch advanced the fixed tick.")
	_assert_equal(world.state_hash(), hash_before, "Rejected batch partially mutated world state.")
	_assert_equal(
		world.presentation_snapshot().entities_as_dictionaries(),
		snapshot_before.entities_as_dictionaries(),
		"Rejected batch changed presentation state."
	)

	var retry: RefCounted = world.advance_tick([
		_command(2, 1, "command.aim", Vector2.UP, -1, 2),
	])
	_assert_true(retry.is_success(), "Rejected batch consumed an earlier valid sequence.")
	var hash_before_damage: String = world.state_hash()
	var invalid_damage: RefCounted = world.advance_tick(
		[_command(3, 1, "command.move", Vector2.LEFT, -1, 3)],
		[DamageResult.new()]
	)
	_assert_rejected(invalid_damage, "damage.invalid_result", "Invalid damage was accepted.")
	_assert_equal(world.tick(), 2, "Rejected damage advanced the fixed tick.")
	_assert_equal(world.state_hash(), hash_before_damage, "Rejected damage mutated world state.")

	var duplicate: RefCounted = world.advance_tick([
		_command(3, 1, "command.move", Vector2.LEFT, -1, 2),
	])
	_assert_rejected(duplicate, "command.duplicate_sequence", "Duplicate sequence was accepted.")
	var regression: RefCounted = world.advance_tick([
		_command(3, 1, "command.move", Vector2.LEFT, -1, 1),
	])
	_assert_rejected(regression, "command.non_monotonic_sequence", "Regressed sequence was accepted.")
	var late: RefCounted = world.advance_tick([
		_command(2, 1, "command.move", Vector2.LEFT, -1, 3),
	])
	_assert_rejected(late, "command.late_tick", "Late command was accepted.")
	var future: RefCounted = world.advance_tick([
		_command(4, 1, "command.move", Vector2.LEFT, -1, 3),
	])
	_assert_rejected(future, "command.future_tick", "Future command was accepted.")
	var missing: RefCounted = world.advance_tick([
		_command(3, 99, "command.move", Vector2.LEFT, -1, 1),
	])
	_assert_rejected(missing, "command.unknown_actor", "Unknown actor command was accepted.")
	var enemy: RefCounted = world.advance_tick([
		_command(3, 2, "command.aim", Vector2.LEFT, -1, 1),
	])
	_assert_rejected(enemy, "command.actor_not_player", "Non-player command was accepted.")
	var malformed: RefCounted = world.advance_tick([PlayerCommand.new()])
	_assert_rejected(malformed, "command.invalid", "Unconfigured command was accepted.")
	_assert_equal(world.tick(), 2, "Rejected paths must preserve the last accepted tick.")


func _test_cast_sequence_contract() -> void:
	var world := _world()
	var double_start: RefCounted = world.advance_tick([
		_command(1, 1, "command.cast_start", Vector2.RIGHT, 0, 1),
		_command(1, 1, "command.cast_start", Vector2.RIGHT, 1, 2),
	])
	_assert_rejected(double_start, "command.impossible_sequence", "Double cast start was accepted.")
	_assert_equal(world.tick(), 0, "Rejected double start partially committed its first command.")

	_assert_true(world.advance_tick([
		_command(1, 1, "command.cast_start", Vector2.RIGHT, 0, 1),
	]).is_success(), "Valid cast start failed.")
	var wrong_release: RefCounted = world.advance_tick([
		_command(2, 1, "command.cast_release", Vector2.RIGHT, 1, 2),
	])
	_assert_rejected(wrong_release, "command.impossible_sequence", "Mismatched release was accepted.")
	_assert_true(world.advance_tick([
		_command(2, 1, "command.cancel", Vector2.ZERO, -1, 2),
	]).is_success(), "Valid cancellation failed.")
	_assert_equal(
		world.presentation_snapshot().entity(1).cast_phase(),
		"cast.canceled",
		"Cancellation phase was not published."
	)
	_assert_true(world.advance_tick([]).is_success(), "Empty fixed tick failed.")
	_assert_equal(
		world.presentation_snapshot().entity(1).cast_phase(),
		"cast.idle",
		"Canceled phase did not return to idle."
	)


func _test_presentation_snapshots_are_read_only() -> void:
	var world := _world()
	_assert_true(world.advance_tick([]).is_success(), "Empty snapshot tick failed.")
	var snapshot: RefCounted = world.presentation_snapshot()
	var leaked: Array = snapshot.entities()
	_assert_equal(
		[leaked[0].runtime_id(), leaked[1].runtime_id()],
		[1, 2],
		"Presentation entities must be sorted by runtime ID."
	)
	leaked.clear()
	_assert_equal(snapshot.entities().size(), 2, "Snapshot exposed mutable entity storage.")
	var dictionaries: Array = snapshot.entities_as_dictionaries()
	dictionaries[0]["health"] = 0
	_assert_equal(snapshot.entity(1).health(), 100, "Snapshot dictionary mutated a published entity.")

	var leaked_state: RefCounted = world.entity_state(1)
	var injected := PlayerCommand.new()
	_assert_equal(
		injected.configure(2, 1, "command.move", Vector2.LEFT, -1, 1),
		"",
		"Test command configuration failed."
	)
	leaked_state._begin_tick()
	_assert_equal(world.entity_state(1).movement_input(), Vector2.ZERO, "World exposed mutable entity state.")
	_assert_equal(snapshot.state_hash(), world.state_hash(), "Read-only access changed the world hash.")


func _test_entity_world_configuration_is_transactional() -> void:
	var duplicate := EntityWorld.new()
	var player := _player()
	_assert_contains(
		duplicate.configure([player, player]),
		"Duplicate runtime entity",
		"Duplicate runtime IDs must reject world configuration."
	)
	_assert_equal(duplicate.tick(), -1, "Rejected world configuration published a tick.")
	var isolated := EntityWorld.new()
	_assert_equal(isolated.configure([player]), "", "Isolated world configuration failed.")
	var direct_command := _command(1, 1, "command.move", Vector2.LEFT, -1, 1)
	_assert_equal(player._apply_command(direct_command), "", "Source entity mutation failed.")
	_assert_equal(
		isolated.entity_state(1).movement_input(),
		Vector2.ZERO,
		"World retained mutable initial entity storage."
	)

	var invalid := EntityState.new()
	_assert_contains(
		invalid.configure(0, "Entity.Invalid", true, Vector2.ZERO, 1, 1, 0.0, 0.0),
		"positive",
		"Invalid runtime entity state was accepted."
	)
	var world := EntityWorld.new()
	_assert_contains(world.configure([invalid]), "configured", "Invalid entity was published.")


func _world() -> RefCounted:
	var world := EntityWorld.new()
	var error: String = world.configure([_enemy(), _player()])
	_assert_equal(error, "", "Entity world configuration failed.")
	return world


func _player() -> RefCounted:
	var entity := EntityState.new()
	var error: String = entity.configure(
		1,
		"entity.player.stormweaver",
		true,
		Vector2(10.0, 20.0),
		100,
		100,
		50.0,
		50.0
	)
	_assert_equal(error, "", "Player entity configuration failed.")
	return entity


func _enemy() -> RefCounted:
	var entity := EntityState.new()
	var error: String = entity.configure(
		2,
		"entity.enemy.training_dummy",
		false,
		Vector2(30.0, 20.0),
		250,
		250,
		0.0,
		0.0,
		Vector2.LEFT
	)
	_assert_equal(error, "", "Enemy entity configuration failed.")
	return entity


func _command(
	tick: int,
	actor_id: int,
	command_type: String,
	aim_vector: Vector2,
	ability_slot: int,
	client_sequence: int
) -> RefCounted:
	var command := PlayerCommand.new()
	var error: String = command.configure(
		tick, actor_id, command_type, aim_vector, ability_slot, client_sequence
	)
	_assert_equal(error, "", "Test command configuration failed.")
	return command


func _commands_from_batch(batch: Dictionary) -> Array:
	var commands: Array = []
	for value: Dictionary in batch.get("commands", []):
		var command := PlayerCommand.new()
		var error: String = command.configure_from_dictionary(value)
		_assert_equal(error, "", "Replay command fixture is invalid.")
		commands.append(command)
	return commands


func _load_fixture() -> Dictionary:
	var contents := FileAccess.get_file_as_string(FIXTURE_PATH)
	var parsed: Variant = JSON.parse_string(contents)
	if not parsed is Dictionary:
		failures.append("Replay fixture must parse as a Dictionary.")
		return {}
	return parsed


func _assert_rejected(result: RefCounted, code: String, message: String) -> void:
	if result.is_success():
		failures.append(message)
		return
	var diagnostics: Array = result.diagnostics()
	if diagnostics.size() != 1 or diagnostics[0].get("code") != code:
		failures.append("%s Expected diagnostic %s, got %s." % [message, code, diagnostics])
	if result.accepted_count() != 0:
		failures.append("Rejected command batch reported partial acceptance.")


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])
