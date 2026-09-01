extends SceneTree

const CommandAdapter = preload("res://game/presentation/input/keyboard_mouse_command_adapter.gd")
const EntityState = preload("res://game/simulation/entities/entity_state.gd")
const EntityWorld = preload("res://game/simulation/entities/entity_world.gd")
const MovementEnvironment = preload("res://game/simulation/movement/movement_environment.gd")
const PlayerCommand = preload("res://game/simulation/commands/player_command.gd")

const EXPECTED_MOVEMENT_REPLAY_HASH := "ccbb94ed2230576cb4a4dcf5b6a3ab7f0ad9006572435b51c44601c5fe52fd7d"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_input_actions_and_command_emission()
	_test_fixed_tick_collision_and_wall_sliding()
	_test_boundaries_and_obstacle_order_are_deterministic()
	_test_world_configuration_rejects_invalid_placement()
	_test_rendered_and_headless_hashes_match()

	if failures.is_empty():
		print("Production player movement tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_input_actions_and_command_emission() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		_assert_true(InputMap.has_action(action), "Missing InputMap action %s." % action)

	var adapter := CommandAdapter.new()
	_assert_equal(adapter.configure(7), "", "Input adapter configuration failed.")
	var first: Dictionary = adapter.commands_from_sample(
		1,
		Vector2(2.0, 0.0),
		Vector2(10.0, 10.0),
		Vector2(10.0, 0.0)
	)
	_assert_equal(first.get("error"), "", "Valid input sample was rejected.")
	var first_commands: Array = first.get("commands", [])
	_assert_equal(first_commands.size(), 2, "First sample must emit move and aim commands.")
	if first_commands.size() == 2:
		_assert_equal(first_commands[0].command_type(), PlayerCommand.MOVE, "Move command order changed.")
		_assert_equal(first_commands[0].aim_vector(), Vector2.RIGHT, "Movement was not normalized.")
		_assert_equal(first_commands[0].client_sequence(), 1, "Move sequence must start at one.")
		_assert_equal(first_commands[1].command_type(), PlayerCommand.AIM, "Aim command order changed.")
		_assert_equal(first_commands[1].aim_vector(), Vector2.UP, "Mouse aim was not world-relative.")
		_assert_equal(first_commands[1].client_sequence(), 2, "Aim sequence must follow movement.")

	var unchanged: Dictionary = adapter.commands_from_sample(
		2,
		Vector2.RIGHT,
		Vector2(20.0, 10.0),
		Vector2(20.0, 0.0)
	)
	_assert_equal(unchanged.get("commands", []).size(), 0, "Unchanged intent must be suppressed.")

	var stopped: Dictionary = adapter.commands_from_sample(
		3,
		Vector2.ZERO,
		Vector2(20.0, 10.0),
		Vector2(20.0, 0.0)
	)
	var stop_commands: Array = stopped.get("commands", [])
	_assert_equal(stop_commands.size(), 1, "Neutral movement must emit one stop command.")
	if stop_commands.size() == 1:
		_assert_equal(stop_commands[0].command_type(), PlayerCommand.MOVE, "Stop must remain a move command.")
		_assert_equal(stop_commands[0].aim_vector(), Vector2.ZERO, "Stop command must carry zero movement.")
		_assert_equal(stop_commands[0].client_sequence(), 3, "Suppressed input consumed a sequence.")

	var invalid: Dictionary = adapter.commands_from_sample(
		4,
		Vector2(INF, 0.0),
		Vector2.ZERO,
		Vector2.RIGHT
	)
	_assert_contains(invalid.get("error", ""), "finite", "Non-finite input was accepted.")
	_assert_equal(adapter.next_client_sequence(), 4, "Rejected input consumed a client sequence.")
	adapter.free()


func _test_fixed_tick_collision_and_wall_sliding() -> void:
	var environment := _environment(
		Rect2(0.0, 0.0, 100.0, 100.0),
		[Rect2(40.0, 20.0, 10.0, 60.0)],
		5.0,
		600.0
	)
	var world := _world(Vector2(30.0, 50.0), environment)
	_assert_true(
		world.advance_tick([_command(1, Vector2.RIGHT, 1)]).is_success(),
		"Movement tick failed."
	)
	_assert_vector_close(
		world.entity_state(1).position(),
		Vector2(35.0, 50.0),
		"Continuous sweep did not stop at the expanded obstacle."
	)
	_assert_true(world.advance_tick([]).is_success(), "Persistent movement tick failed.")
	_assert_vector_close(
		world.entity_state(1).position(),
		Vector2(35.0, 50.0),
		"Persistent input tunneled through the obstacle."
	)
	_assert_true(
		world.advance_tick([_command(3, Vector2.DOWN, 2)]).is_success(),
		"Wall-slide command failed."
	)
	_assert_vector_close(
		world.entity_state(1).position(),
		Vector2(35.0, 60.0),
		"Movement did not slide along the obstacle boundary."
	)


func _test_boundaries_and_obstacle_order_are_deterministic() -> void:
	var first := _environment(
		Rect2(0.0, 0.0, 100.0, 100.0),
		[Rect2(70.0, 20.0, 10.0, 10.0), Rect2(40.0, 20.0, 10.0, 60.0)],
		5.0,
		6000.0
	)
	var second := _environment(
		Rect2(0.0, 0.0, 100.0, 100.0),
		[Rect2(40.0, 20.0, 10.0, 60.0), Rect2(70.0, 20.0, 10.0, 10.0)],
		5.0,
		6000.0
	)
	_assert_equal(first.canonical_values(), second.canonical_values(), "Obstacle order changed canonical state.")
	var first_world := _world(Vector2(10.0, 50.0), first)
	var second_world := _world(Vector2(10.0, 50.0), second)
	_assert_true(first_world.advance_tick([_command(1, Vector2.RIGHT, 1)]).is_success(), "First sweep failed.")
	_assert_true(second_world.advance_tick([_command(1, Vector2.RIGHT, 1)]).is_success(), "Second sweep failed.")
	_assert_vector_close(first_world.entity_state(1).position(), Vector2(35.0, 50.0), "Fast movement tunneled.")
	_assert_equal(first_world.state_hash(), second_world.state_hash(), "Authored obstacle order changed state hash.")

	var boundary_environment := _environment(Rect2(0.0, 0.0, 100.0, 100.0), [], 5.0, 600.0)
	var boundary_world := _world(Vector2(90.0, 90.0), boundary_environment)
	_assert_true(
		boundary_world.advance_tick([_command(1, Vector2(1.0, 1.0).normalized(), 1)]).is_success(),
		"Boundary movement failed."
	)
	_assert_vector_close(
		boundary_world.entity_state(1).position(),
		Vector2(95.0, 95.0),
		"Actor radius was not enforced at arena bounds."
	)


func _test_world_configuration_rejects_invalid_placement() -> void:
	var environment := _environment(
		Rect2(0.0, 0.0, 100.0, 100.0),
		[Rect2(40.0, 20.0, 10.0, 60.0)],
		5.0,
		600.0
	)
	var world := EntityWorld.new()
	_assert_contains(
		world.configure([_player(Vector2(45.0, 50.0))], 0, environment),
		"placement",
		"Entity inside an expanded obstacle was accepted."
	)
	_assert_equal(world.tick(), -1, "Rejected placement partially configured the world.")


func _test_rendered_and_headless_hashes_match() -> void:
	var rendered_environment := _environment(
		Rect2(0.0, 0.0, 200.0, 200.0),
		[Rect2(80.0, 40.0, 20.0, 120.0)],
		4.0,
		360.0
	)
	var headless_environment := _environment(
		Rect2(0.0, 0.0, 200.0, 200.0),
		[Rect2(80.0, 40.0, 20.0, 120.0)],
		4.0,
		360.0
	)
	var rendered := _world(Vector2(20.0, 80.0), rendered_environment)
	var headless := _world(Vector2(20.0, 80.0), headless_environment)
	var batches := [
		[_command(1, Vector2.RIGHT, 1)],
		[],
		[_command(3, Vector2(1.0, 1.0).normalized(), 2)],
		[],
	]
	for batch: Array in batches:
		var rendered_result: RefCounted = rendered.advance_tick(batch)
		var headless_result: RefCounted = headless.advance_tick(_duplicate_commands(batch))
		_assert_true(rendered_result.is_success(), "Rendered replay tick failed.")
		_assert_true(headless_result.is_success(), "Headless replay tick failed.")
		var snapshot: RefCounted = rendered.presentation_snapshot()
		_assert_equal(snapshot.state_hash(), rendered.state_hash(), "Snapshot hash diverged from world hash.")
		_assert_equal(rendered.state_hash(), headless.state_hash(), "Presentation access changed movement state.")
		_assert_vector_close(
			snapshot.entity(1).position(),
			headless.entity_state(1).position(),
			"Rendered and headless positions diverged."
		)
	_assert_equal(
		headless.state_hash(),
		EXPECTED_MOVEMENT_REPLAY_HASH,
		"Movement replay golden hash changed."
	)


func _environment(
	bounds: Rect2,
	obstacles: Array,
	actor_radius: float,
	speed_per_second: float
) -> RefCounted:
	var environment := MovementEnvironment.new()
	_assert_equal(
		environment.configure(bounds, obstacles, actor_radius, speed_per_second),
		"",
		"Movement environment configuration failed."
	)
	return environment


func _world(position: Vector2, environment: RefCounted) -> RefCounted:
	var world := EntityWorld.new()
	_assert_equal(
		world.configure([_player(position)], 0, environment),
		"",
		"Movement world configuration failed."
	)
	return world


func _player(position: Vector2) -> RefCounted:
	var entity := EntityState.new()
	_assert_equal(
		entity.configure(1, "entity.player.stormweaver", true, position, 100, 100, 50.0, 50.0),
		"",
		"Player configuration failed."
	)
	return entity


func _command(tick: int, movement: Vector2, sequence: int) -> RefCounted:
	var command := PlayerCommand.new()
	_assert_equal(
		command.configure(tick, 1, PlayerCommand.MOVE, movement, -1, sequence),
		"",
		"Movement command configuration failed."
	)
	return command


func _duplicate_commands(commands: Array) -> Array:
	var result: Array = []
	for command: RefCounted in commands:
		var copy := PlayerCommand.new()
		_assert_equal(copy.configure_from_dictionary(command.to_dictionary()), "", "Command copy failed.")
		result.append(copy)
	return result


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])


func _assert_vector_close(actual: Vector2, expected: Vector2, message: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])
