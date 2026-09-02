extends SceneTree

const AbilityCastBinding = preload(
	"res://game/simulation/abilities/ability_cast_binding.gd"
)
const AbilityDefinition = preload(
	"res://game/simulation/abilities/ability_definition.gd"
)
const AbilityEffectDefinition = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const AbilityLoadout = preload(
	"res://game/simulation/abilities/ability_loadout.gd"
)
const CastInterruption = preload(
	"res://game/simulation/abilities/cast_interruption.gd"
)
const EntityState = preload("res://game/simulation/entities/entity_state.gd")
const EntityWorld = preload("res://game/simulation/entities/entity_world.gd")
const MovementEnvironment = preload(
	"res://game/simulation/movement/movement_environment.gd"
)
const PlayerCommand = preload("res://game/simulation/commands/player_command.gd")

const EXPECTED_CAST_REPLAY_HASH := "3f4a330d75b3f436e487b46e832039da30214844a701c543a5bcdb1d9f987af7"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_binding_and_loadout_validation()
	_test_cast_timing_cost_cooldown_and_recovery()
	_test_invalid_casts_are_atomic()
	_test_movement_policies()
	_test_manual_and_external_interruptions()
	_test_tempest_dash_can_cancel_into_a_new_cast()
	_test_rendered_and_headless_hashes_match()

	if failures.is_empty():
		print("Production cast runtime tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_binding_and_loadout_validation() -> void:
	var binding := _binding(
		0,
		_ability("ability.test.validation", 5.0, 1, 0, 0),
		AbilityCastBinding.MovementPolicy.ALLOW,
		true,
		PackedStringArray(["interrupt.control"]),
		false
	)
	var duplicate := AbilityLoadout.new()
	_assert_contains(
		duplicate.configure("resource.mana", [binding, binding]),
		"Duplicate",
		"Duplicate loadout slots were accepted."
	)
	_assert_equal(
		duplicate.configure("resource.mana", [binding]),
		"",
		"Rejected loadout configuration was not transactional."
	)
	var mismatched := AbilityLoadout.new()
	_assert_contains(
		mismatched.configure("resource.energy", [binding]),
		"not loadout resource",
		"Mismatched resource ownership was accepted."
	)
	_assert_contains(
		binding.configure(
			1,
			binding.ability(),
			AbilityCastBinding.MovementPolicy.LOCK,
			false,
			PackedStringArray(),
			false
		),
		"immutable",
		"Published cast binding accepted mutation."
	)


func _test_cast_timing_cost_cooldown_and_recovery() -> void:
	var binding := _binding(
		0,
		_ability("ability.test.storm_lance", 20.0, 4, 2, 2),
		AbilityCastBinding.MovementPolicy.LOCK,
		true,
		PackedStringArray(["interrupt.control"]),
		false
	)
	var world := _world(50.0, _loadout([binding]))
	_assert_success(
		world.advance_tick([_command(1, PlayerCommand.CAST_START, 0, 1)]),
		"Cast start failed."
	)
	var started: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(started.cast_phase(), "cast.started", "Cast did not enter started phase.")
	_assert_equal(started.cast_ticks_remaining(), 2, "Cast ready countdown is wrong.")
	_assert_float(started.resource(), 50.0, "Cast start spent resource early.")

	var early_release: RefCounted = world.advance_tick([
		_command(2, PlayerCommand.CAST_RELEASE, 0, 2),
	])
	_assert_rejected_contains(early_release, "not ready", "Early release was accepted.")
	_assert_equal(world.tick(), 1, "Early release advanced the world.")
	_assert_float(world.entity_state(1).resource(), 50.0, "Early release spent resource.")

	_assert_success(world.advance_tick([]), "Cast countdown tick failed.")
	_assert_equal(
		world.presentation_snapshot().entity(1).cast_ticks_remaining(),
		1,
		"Cast countdown did not advance by one tick."
	)
	_assert_success(
		world.advance_tick([_command(3, PlayerCommand.CAST_RELEASE, 0, 2)]),
		"Ready cast release failed."
	)
	var released: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(released.cast_phase(), "cast.released", "Release was not observable.")
	_assert_float(released.resource(), 30.0, "Release did not spend the exact cost.")
	_assert_equal(released.cooldown_ticks_remaining(0), 4, "Cooldown did not start on release.")
	_assert_equal(released.recovery_ticks_remaining(), 2, "Recovery duration is wrong.")
	var leaked_cooldowns: Array = released.cooldowns()
	leaked_cooldowns[0]["end_tick"] = 0
	_assert_equal(released.cooldown_ticks_remaining(0), 4, "Snapshot cooldown storage was mutable.")

	_assert_success(world.advance_tick([]), "First recovery tick failed.")
	_assert_equal(world.entity_state(1).cast_phase(), "cast.recovering", "Recovery did not start.")
	_assert_success(world.advance_tick([]), "Second recovery tick failed.")
	_assert_equal(world.entity_state(1).cast_phase(), "cast.recovering", "Recovery ended too early.")
	_assert_success(world.advance_tick([]), "Recovery completion tick failed.")
	var recovered: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(recovered.cast_phase(), "cast.idle", "Recovery did not return to idle.")
	_assert_equal(recovered.cooldown_ticks_remaining(0), 1, "Cooldown countdown is wrong.")
	_assert_success(
		world.advance_tick([_command(7, PlayerCommand.CAST_START, 0, 3)]),
		"Cast was unavailable when cooldown reached zero."
	)


func _test_invalid_casts_are_atomic() -> void:
	var binding := _binding(
		0,
		_ability("ability.test.arc_bolt", 10.0, 5, 0, 0),
		AbilityCastBinding.MovementPolicy.ALLOW,
		true,
		PackedStringArray(),
		false
	)
	var poor_world := _world(0.0, _loadout([binding]))
	var poor_start: RefCounted = poor_world.advance_tick([
		_command(1, PlayerCommand.CAST_START, 0, 1),
	])
	_assert_rejected_contains(poor_start, "resource", "Zero-resource cast was accepted.")
	_assert_equal(poor_world.tick(), 0, "Rejected resource check advanced the tick.")
	_assert_float(poor_world.entity_state(1).resource(), 0.0, "Rejected cast changed resource.")

	var atomic_world := _world(20.0, _loadout([binding]))
	var partial_batch: RefCounted = atomic_world.advance_tick([
		_command(1, PlayerCommand.CAST_START, 0, 1),
		_command(1, PlayerCommand.CAST_RELEASE, 0, 2),
		_command(1, PlayerCommand.CAST_START, 0, 3),
	])
	_assert_rejected_contains(partial_batch, "active cast", "Invalid chained cast was accepted.")
	_assert_equal(atomic_world.tick(), 0, "Rejected batch partially advanced the tick.")
	_assert_float(atomic_world.entity_state(1).resource(), 20.0, "Rejected batch partially spent resource.")
	_assert_equal(atomic_world.entity_state(1).cast_phase(), "cast.idle", "Rejected batch retained cast state.")

	_assert_success(
		atomic_world.advance_tick([
			_command(1, PlayerCommand.CAST_START, 0, 1),
			_command(1, PlayerCommand.CAST_RELEASE, 0, 2),
		]),
		"Instant cast batch failed."
	)
	var hash_before: String = atomic_world.state_hash()
	var cooldown_retry: RefCounted = atomic_world.advance_tick([
		_command(2, PlayerCommand.CAST_START, 0, 3),
	])
	_assert_rejected_contains(cooldown_retry, "cooldown", "Cooldown cast was accepted.")
	_assert_equal(atomic_world.state_hash(), hash_before, "Cooldown rejection mutated state.")
	_assert_float(atomic_world.entity_state(1).resource(), 10.0, "Cooldown rejection spent resource.")


func _test_movement_policies() -> void:
	var locked := _binding(
		0,
		_ability("ability.test.locked_cast", 0.0, 0, 10, 0),
		AbilityCastBinding.MovementPolicy.LOCK,
		true,
		PackedStringArray(),
		false
	)
	var cancel_on_move := _binding(
		1,
		_ability("ability.test.mobile_cancel", 0.0, 0, 10, 0),
		AbilityCastBinding.MovementPolicy.CANCEL_CAST,
		true,
		PackedStringArray(),
		false
	)
	var environment := MovementEnvironment.new()
	_assert_equal(
		environment.configure(Rect2(0.0, 0.0, 100.0, 100.0), [], 1.0, 60.0),
		"",
		"Movement environment configuration failed."
	)
	var world := _world(10.0, _loadout([locked, cancel_on_move]), environment)
	_assert_success(
		world.advance_tick([_command(1, PlayerCommand.MOVE, -1, 1, Vector2.RIGHT)]),
		"Initial movement failed."
	)
	_assert_vector_close(world.entity_state(1).position(), Vector2(11.0, 10.0), "Initial movement is wrong.")
	_assert_success(
		world.advance_tick([_command(2, PlayerCommand.CAST_START, 0, 2)]),
		"Locked cast start failed."
	)
	_assert_equal(world.entity_state(1).movement_input(), Vector2.ZERO, "Locked cast did not stop retained movement.")
	_assert_vector_close(world.entity_state(1).position(), Vector2(11.0, 10.0), "Locked cast moved the actor.")

	var blocked_move: RefCounted = world.advance_tick([
		_command(3, PlayerCommand.MOVE, -1, 3, Vector2.RIGHT),
	])
	_assert_rejected_contains(blocked_move, "locks movement", "Movement bypassed a locked cast.")
	_assert_equal(world.tick(), 2, "Blocked movement advanced the tick.")
	_assert_success(
		world.advance_tick([_command(3, PlayerCommand.CANCEL, -1, 3)]),
		"Manual cancel of locked cast failed."
	)
	_assert_success(
		world.advance_tick([_command(4, PlayerCommand.CAST_START, 1, 4)]),
		"Cancel-on-move cast start failed."
	)
	_assert_success(
		world.advance_tick([_command(5, PlayerCommand.MOVE, -1, 5, Vector2.DOWN)]),
		"Cancel-on-move transition failed."
	)
	var canceled: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(canceled.cast_phase(), "cast.canceled", "Movement did not cancel the cast.")
	_assert_equal(canceled.last_cancel_reason(), "interrupt.movement", "Movement cancel reason is wrong.")
	_assert_vector_close(canceled.position(), Vector2(11.0, 11.0), "Canceling movement was not integrated.")


func _test_manual_and_external_interruptions() -> void:
	var binding := _binding(
		0,
		_ability("ability.test.interruptible", 0.0, 0, 10, 0),
		AbilityCastBinding.MovementPolicy.ALLOW,
		false,
		PackedStringArray(["interrupt.control"]),
		false
	)
	var world := _world(10.0, _loadout([binding]))
	_assert_success(
		world.advance_tick([_command(1, PlayerCommand.CAST_START, 0, 1)]),
		"Interruptible cast start failed."
	)
	_assert_success(
		world.advance_tick([], [], [_interruption("interrupt.damage")]),
		"Ignored interruption failed the tick."
	)
	_assert_equal(world.entity_state(1).cast_phase(), "cast.started", "Unlisted interruption canceled the cast.")

	var manual: RefCounted = world.advance_tick([
		_command(3, PlayerCommand.CANCEL, -1, 2),
	])
	_assert_rejected_contains(manual, "manual cancellation", "Forbidden manual cancel was accepted.")
	_assert_equal(world.tick(), 2, "Forbidden manual cancel advanced the tick.")
	_assert_success(
		world.advance_tick([], [], [_interruption("interrupt.control")]),
		"Allowed interruption failed."
	)
	var canceled: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(canceled.cast_phase(), "cast.canceled", "Allowed interruption did not cancel.")
	_assert_equal(canceled.last_cancel_reason(), "interrupt.control", "Interruption reason was not retained.")


func _test_tempest_dash_can_cancel_into_a_new_cast() -> void:
	var channel := _binding(
		0,
		_ability("ability.test.channel", 0.0, 0, 30, 0),
		AbilityCastBinding.MovementPolicy.LOCK,
		true,
		PackedStringArray(["interrupt.ability_replaced"]),
		false
	)
	var dash := _binding(
		5,
		_ability("ability.stormweaver.tempest_dash", 5.0, 30, 0, 0),
		AbilityCastBinding.MovementPolicy.ALLOW,
		false,
		PackedStringArray(["interrupt.control"]),
		true
	)
	var loadout := _loadout([channel, dash])
	var reversed_loadout := _loadout([dash, channel])
	_assert_equal(
		loadout.canonical_values(),
		reversed_loadout.canonical_values(),
		"Loadout authored order changed canonical state."
	)
	_assert_true(dash.cancels_active_cast(), "Tempest Dash cannot represent cancel-into-cast.")
	_assert_equal(dash.movement_policy(), AbilityCastBinding.MovementPolicy.ALLOW, "Dash movement policy is wrong.")
	var world := _world(20.0, loadout)
	_assert_success(
		world.advance_tick([_command(1, PlayerCommand.CAST_START, 0, 1)]),
		"Channel cast start failed."
	)
	_assert_success(
		world.advance_tick([_command(2, PlayerCommand.CAST_START, 5, 2)]),
		"Tempest Dash did not cancel into its cast."
	)
	var snapshot: RefCounted = world.presentation_snapshot().entity(1)
	_assert_equal(snapshot.cast_phase(), "cast.started", "Dash did not enter started phase.")
	_assert_equal(snapshot.ability_slot(), 5, "Dash did not replace the active slot.")
	_assert_equal(snapshot.last_cancel_reason(), "interrupt.ability_replaced", "Replacement reason is wrong.")
	_assert_float(snapshot.resource(), 20.0, "Cancel-into start spent resource before release.")


func _test_rendered_and_headless_hashes_match() -> void:
	var rendered := _world(
		20.0,
		_loadout([_binding(
			0,
			_ability("ability.test.replay", 5.0, 2, 0, 0),
			AbilityCastBinding.MovementPolicy.ALLOW,
			true,
			PackedStringArray(),
			false
		)])
	)
	var headless := _world(
		20.0,
		_loadout([_binding(
			0,
			_ability("ability.test.replay", 5.0, 2, 0, 0),
			AbilityCastBinding.MovementPolicy.ALLOW,
			true,
			PackedStringArray(),
			false
		)])
	)
	var batches := [
		[
			_command(1, PlayerCommand.CAST_START, 0, 1),
			_command(1, PlayerCommand.CAST_RELEASE, 0, 2),
		],
		[],
		[
			_command(3, PlayerCommand.CAST_START, 0, 3),
			_command(3, PlayerCommand.CAST_RELEASE, 0, 4),
		],
	]
	for batch: Array in batches:
		_assert_success(rendered.advance_tick(batch), "Rendered cast replay failed.")
		_assert_success(headless.advance_tick(_duplicate_commands(batch)), "Headless cast replay failed.")
		var snapshot: RefCounted = rendered.presentation_snapshot()
		_assert_equal(snapshot.state_hash(), rendered.state_hash(), "Snapshot cast hash diverged.")
		_assert_equal(rendered.state_hash(), headless.state_hash(), "Rendered/headless cast hashes diverged.")
	_assert_equal(headless.state_hash(), EXPECTED_CAST_REPLAY_HASH, "Cast replay golden hash changed.")


func _ability(
	ability_id: String,
	cost: float,
	cooldown_ticks: int,
	cast_time_ticks: int,
	recovery_ticks: int
) -> RefCounted:
	var effect := AbilityEffectDefinition.new()
	_assert_equal(
		effect.configure_event(
			"effect.%s.cast" % ability_id,
			PackedStringArray(),
			PackedStringArray(),
			"event.cast",
			{}
		),
		"",
		"Ability effect configuration failed."
	)
	var ability := AbilityDefinition.new()
	_assert_equal(
		ability.configure_ability(
			ability_id,
			["ability.test"],
			[],
			"resource.mana" if cost > 0.0 else "",
			cost,
			cooldown_ticks,
			cast_time_ticks,
			recovery_ticks,
			AbilityDefinition.Targeting.DIRECTION,
			AbilityDefinition.Delivery.INSTANT,
			[effect],
			[]
		),
		"",
		"Ability configuration failed."
	)
	return ability


func _binding(
	slot: int,
	ability: RefCounted,
	movement_policy: int,
	manual_cancel_allowed: bool,
	interrupt_reasons: PackedStringArray,
	cancels_active_cast: bool
) -> RefCounted:
	var binding := AbilityCastBinding.new()
	_assert_equal(
		binding.configure(
			slot,
			ability,
			movement_policy,
			manual_cancel_allowed,
			interrupt_reasons,
			cancels_active_cast
		),
		"",
		"Ability binding configuration failed."
	)
	return binding


func _loadout(bindings: Array) -> RefCounted:
	var loadout := AbilityLoadout.new()
	_assert_equal(loadout.configure("resource.mana", bindings), "", "Ability loadout configuration failed.")
	return loadout


func _world(
	resource: float,
	loadout: RefCounted,
	movement_environment: Variant = null
) -> RefCounted:
	var world := EntityWorld.new()
	_assert_equal(
		world.configure([_player(resource)], 0, movement_environment, {1: loadout}),
		"",
		"Cast world configuration failed."
	)
	return world


func _player(resource: float) -> RefCounted:
	var entity := EntityState.new()
	_assert_equal(
		entity.configure(
			1,
			"entity.player.stormweaver",
			true,
			Vector2(10.0, 10.0),
			100,
			100,
			resource,
			maxf(resource, 100.0)
		),
		"",
		"Player configuration failed."
	)
	return entity


func _command(
	tick: int,
	command_type: String,
	slot: int,
	sequence: int,
	vector: Vector2 = Vector2.RIGHT
) -> RefCounted:
	var command := PlayerCommand.new()
	var command_vector := vector
	if command_type == PlayerCommand.CANCEL:
		command_vector = Vector2.ZERO
	_assert_equal(
		command.configure(tick, 1, command_type, command_vector, slot, sequence),
		"",
		"Player command configuration failed."
	)
	return command


func _interruption(reason_id: String) -> RefCounted:
	var interruption := CastInterruption.new()
	_assert_equal(interruption.configure(1, reason_id), "", "Cast interruption configuration failed.")
	return interruption


func _duplicate_commands(commands: Array) -> Array:
	var result: Array = []
	for command: RefCounted in commands:
		var copy := PlayerCommand.new()
		_assert_equal(copy.configure_from_dictionary(command.to_dictionary()), "", "Command copy failed.")
		result.append(copy)
	return result


func _assert_success(result: RefCounted, message: String) -> void:
	if not result.is_success():
		failures.append("%s Diagnostics: %s." % [message, result.diagnostics()])


func _assert_rejected_contains(result: RefCounted, expected: String, message: String) -> void:
	if result.is_success():
		failures.append(message)
		return
	var diagnostics: Array = result.diagnostics()
	if diagnostics.size() != 1 or not str(diagnostics[0].get("message", "")).contains(expected):
		failures.append("%s Expected '%s' in %s." % [message, expected, diagnostics])


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_vector_close(actual: Vector2, expected: Vector2, message: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])
