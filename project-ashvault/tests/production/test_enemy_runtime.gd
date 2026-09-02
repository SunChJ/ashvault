extends SceneTree

const DamageComponent = preload(
	"res://game/simulation/combat/damage_component.gd"
)
const DamageContext = preload(
	"res://game/simulation/combat/damage_context.gd"
)
const DamagePipeline = preload(
	"res://game/simulation/combat/damage_pipeline.gd"
)
const EnemyDefinition = preload(
	"res://game/simulation/enemies/enemy_definition.gd"
)
const EntityState = preload(
	"res://game/simulation/entities/entity_state.gd"
)
const EntityWorld = preload(
	"res://game/simulation/entities/entity_world.gd"
)
const MovementEnvironment = preload(
	"res://game/simulation/movement/movement_environment.gd"
)

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_enemy_definitions_are_typed_and_immutable()
	_test_navigation_stops_at_attack_range_and_bounds()
	_test_contact_range_and_attack_cadence_are_exact()
	_test_target_loss_reacquires_deterministically()
	_test_overkill_and_duplicate_death_emit_one_kill()
	_test_damage_order_does_not_change_kill_credit()
	_test_120_enemy_replay_uses_compact_state()

	if failures.is_empty():
		print("Production enemy runtime tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_enemy_definitions_are_typed_and_immutable() -> void:
	var definition := _enemy_definition("entity.enemy.raider", 6000.0, 10.0, 3)
	_assert_float(definition.movement_speed_per_second(), 6000.0, "Enemy speed is wrong.")
	_assert_equal(definition.attack_cooldown_ticks(), 3, "Enemy cadence is wrong.")
	_assert_contains(
		definition.configure(
			"entity.enemy.changed",
			100.0,
			10.0,
			1.0,
			2.0,
			2,
			"attack.changed"
		),
		"immutable",
		"Configured enemy definitions must reject mutation."
	)
	var invalid := EnemyDefinition.new()
	_assert_contains(
		invalid.configure(
			"entity.enemy.invalid",
			100.0,
			0.0,
			1.0,
			2.0,
			2,
			"attack.invalid"
		),
		"speed",
		"Enemy movement speed must be positive."
	)


func _test_navigation_stops_at_attack_range_and_bounds() -> void:
	var environment := _environment(Rect2(0.0, 0.0, 100.0, 100.0))
	var enemy := _entity(10, "entity.enemy.raider", false, Vector2(5.0, 50.0), 50)
	var player := _entity(1, "entity.player.stormweaver", true, Vector2(95.0, 50.0), 100)
	var world := _world(
		[player, enemy],
		environment,
		{10: _enemy_definition("entity.enemy.raider", 6000.0, 10.0, 3)}
	)
	var moved: RefCounted = world.advance_tick([])

	_assert_true(moved.is_success(), "Enemy navigation tick must succeed.")
	_assert_vector_close(
		world.entity_state(10).position(),
		Vector2(85.0, 50.0),
		"Enemy crossed its attack range or arena bounds."
	)
	_assert_equal(moved.enemy_attack_intents().size(), 0, "Enemy attacked on its movement tick.")
	_assert_equal(world.enemy_target_id(10), 1, "Enemy failed to acquire the player.")


func _test_contact_range_and_attack_cadence_are_exact() -> void:
	var environment := _environment(Rect2(0.0, 0.0, 100.0, 100.0))
	var world := _world(
		[
			_entity(1, "entity.player.stormweaver", true, Vector2(50.0, 50.0), 100),
			_entity(10, "entity.enemy.raider", false, Vector2(40.0, 50.0), 50),
		],
		environment,
		{10: _enemy_definition("entity.enemy.raider", 60.0, 10.0, 3)}
	)
	var first: RefCounted = world.advance_tick([])
	var second: RefCounted = world.advance_tick([])
	var third: RefCounted = world.advance_tick([])
	var fourth: RefCounted = world.advance_tick([])

	_assert_equal(first.enemy_attack_intents().size(), 1, "Inclusive contact range did not attack.")
	_assert_equal(second.enemy_attack_intents().size(), 0, "Enemy attacked before cooldown.")
	_assert_equal(third.enemy_attack_intents().size(), 0, "Enemy attacked one tick early.")
	_assert_equal(fourth.enemy_attack_intents().size(), 1, "Enemy missed its exact cadence tick.")
	var intent: RefCounted = first.enemy_attack_intents()[0]
	_assert_equal(intent.source_entity_id(), 10, "Attack intent source is wrong.")
	_assert_equal(intent.target_entity_id(), 1, "Attack intent target is wrong.")
	_assert_equal(intent.attack_id(), "attack.raider.strike", "Attack intent ID is wrong.")
	_assert_contains(
		intent.configure(9, 10, 1, "attack.changed", Vector2.ZERO, Vector2.ONE),
		"immutable",
		"Published attack intents must reject mutation."
	)


func _test_target_loss_reacquires_deterministically() -> void:
	var environment := _environment(Rect2(0.0, 0.0, 120.0, 120.0))
	var world := _world(
		[
			_entity(1, "entity.player.alpha", true, Vector2(90.0, 50.0), 10),
			_entity(2, "entity.player.beta", true, Vector2(30.0, 50.0), 10),
			_entity(10, "entity.enemy.raider", false, Vector2(10.0, 50.0), 50),
		],
		environment,
		{10: _enemy_definition("entity.enemy.raider", 60.0, 5.0, 3)}
	)
	world.advance_tick([])
	_assert_equal(world.enemy_target_id(10), 2, "Enemy did not choose the nearest player.")
	var after_first_move: Vector2 = world.entity_state(10).position()

	var lost: RefCounted = world.advance_tick(
		[],
		[_damage_result(10, 2, 50.0, 1, "attack.raider.strike")]
	)
	_assert_equal(world.entity_state(2).health(), 0, "Target-loss setup did not kill player two.")
	_assert_equal(world.enemy_target_id(10), 1, "Enemy did not reacquire the remaining player.")
	_assert_true(
		world.entity_state(10).position().x > after_first_move.x,
		"Enemy did not continue toward the replacement target."
	)
	_assert_equal(_kill_events(lost).size(), 1, "Target death did not publish one kill event.")


func _test_overkill_and_duplicate_death_emit_one_kill() -> void:
	var environment := _environment(Rect2(0.0, 0.0, 100.0, 100.0))
	var world := _world(
		[
			_entity(1, "entity.player.stormweaver", true, Vector2(50.0, 50.0), 100),
			_entity(10, "entity.enemy.raider", false, Vector2(60.0, 50.0), 50),
		],
		environment,
		{10: _enemy_definition("entity.enemy.raider", 60.0, 10.0, 3)}
	)
	var lethal: RefCounted = world.advance_tick(
		[],
		[_damage_result(1, 10, 999.0, 7, "ability.arc_bolt")]
	)
	_assert_equal(world.entity_state(10).health(), 0, "Overkill did not clamp health to zero.")
	_assert_equal(_kill_events(lethal).size(), 1, "Lethal transition must emit exactly one kill.")
	_assert_equal(lethal.enemy_attack_intents().size(), 0, "Dead enemy attacked on its death tick.")

	var duplicate: RefCounted = world.advance_tick(
		[],
		[_damage_result(1, 10, 999.0, 8, "ability.arc_bolt")]
	)
	_assert_equal(_kill_events(duplicate).size(), 0, "Damage to a corpse emitted a duplicate kill.")


func _test_damage_order_does_not_change_kill_credit() -> void:
	var environment_a := _environment(Rect2(0.0, 0.0, 100.0, 100.0))
	var environment_b := _environment(Rect2(0.0, 0.0, 100.0, 100.0))
	var entities := [
		_entity(1, "entity.player.alpha", true, Vector2(20.0, 50.0), 100),
		_entity(2, "entity.player.beta", true, Vector2(30.0, 50.0), 100),
		_entity(10, "entity.enemy.raider", false, Vector2(60.0, 50.0), 50),
	]
	var profile_a := _enemy_definition("entity.enemy.raider", 60.0, 5.0, 3)
	var profile_b := _enemy_definition("entity.enemy.raider", 60.0, 5.0, 3)
	var left := _world(entities, environment_a, {10: profile_a})
	var reversed_entities := entities.duplicate()
	reversed_entities.reverse()
	var right := _world(reversed_entities, environment_b, {10: profile_b})
	var early_left := _damage_result(2, 10, 60.0, 1, "ability.beta")
	var late_left := _damage_result(1, 10, 60.0, 2, "ability.alpha")
	var early_right := _damage_result(2, 10, 60.0, 1, "ability.beta")
	var late_right := _damage_result(1, 10, 60.0, 2, "ability.alpha")
	var left_result: RefCounted = left.advance_tick([], [late_left, early_left])
	var right_result: RefCounted = right.advance_tick([], [early_right, late_right])

	_assert_equal(_kill_sources(left_result), [2], "Kill credit ignored origin-event order.")
	_assert_equal(_kill_sources(left_result), _kill_sources(right_result), "Input order changed kill credit.")
	_assert_equal(left.state_hash(), right.state_hash(), "Damage input order changed enemy replay state.")


func _test_120_enemy_replay_uses_compact_state() -> void:
	var left_entities: Array = [
		_entity(1, "entity.player.stormweaver", true, Vector2(190.0, 190.0), 100)
	]
	var right_entities: Array = [
		_entity(1, "entity.player.stormweaver", true, Vector2(190.0, 190.0), 100)
	]
	var left_profiles: Dictionary = {}
	var right_profiles: Dictionary = {}
	for index in 120:
		var runtime_id := index + 2
		var position := Vector2(10.0 + float(index % 12) * 10.0, 10.0 + float(index / 12) * 10.0)
		left_entities.append(_entity(runtime_id, "entity.enemy.swarm", false, position, 20))
		right_entities.append(_entity(runtime_id, "entity.enemy.swarm", false, position, 20))
		left_profiles[runtime_id] = _enemy_definition("entity.enemy.swarm", 120.0, 1.0, 10)
	for runtime_id in range(121, 1, -1):
		right_profiles[runtime_id] = _enemy_definition("entity.enemy.swarm", 120.0, 1.0, 10)
	right_entities.reverse()
	var left := _world(
		left_entities,
		_environment(Rect2(0.0, 0.0, 200.0, 200.0)),
		left_profiles
	)
	var right := _world(
		right_entities,
		_environment(Rect2(0.0, 0.0, 200.0, 200.0)),
		right_profiles
	)
	var left_result: RefCounted = left.advance_tick([])
	var right_result: RefCounted = right.advance_tick([])

	_assert_true(left_result.is_success(), "120-enemy tick must succeed.")
	_assert_equal(left.entity_count(), 121, "Density world lost entities.")
	_assert_equal(left.enemy_runtime_values().size(), 120, "Density world lost enemy runtime values.")
	_assert_true(not left.entity_state(2) is Node, "Enemy runtime must not allocate Nodes.")
	_assert_equal(left.state_hash(), right.state_hash(), "Density replay depends on input order.")
	_assert_equal(
		left.state_hash(),
		"e2772aa8f85a9348dd1a607d3e43447701457647203efd6dba6674a578228b67",
		"Enemy state hash contract changed. Positions: %s."
		% JSON.stringify(_entity_positions(left))
	)


func _world(
	entities: Array,
	environment: RefCounted,
	enemy_definitions: Dictionary
) -> RefCounted:
	var world := EntityWorld.new()
	_assert_equal(
		world.configure(entities, 0, environment, {}, enemy_definitions),
		"",
		"Enemy entity world must configure."
	)
	return world


func _environment(bounds: Rect2) -> RefCounted:
	var environment := MovementEnvironment.new()
	_assert_equal(
		environment.configure(bounds, [], 2.0, 60.0),
		"",
		"Enemy movement environment must configure."
	)
	return environment


func _enemy_definition(
	definition_id: String,
	movement_speed: float,
	attack_range: float,
	attack_cooldown_ticks: int
) -> RefCounted:
	var definition := EnemyDefinition.new()
	var suffix := definition_id.trim_prefix("entity.enemy.")
	_assert_equal(
		definition.configure(
			definition_id,
			500.0,
			movement_speed,
			1.0,
			attack_range,
			attack_cooldown_ticks,
			"attack.%s.strike" % suffix
		),
		"",
		"Enemy definition must configure."
	)
	return definition


func _entity(
	runtime_id: int,
	definition_id: String,
	is_player: bool,
	position: Vector2,
	health: int
) -> RefCounted:
	var entity := EntityState.new()
	_assert_equal(
		entity.configure(
			runtime_id,
			definition_id,
			is_player,
			position,
			health,
			health,
			0.0,
			0.0
		),
		"",
		"Enemy fixture entity must configure."
	)
	return entity


func _damage_result(
	source_entity_id: int,
	target_entity_id: int,
	amount: float,
	origin_event_id: int,
	ability_id: String
) -> RefCounted:
	var component := DamageComponent.new()
	_assert_equal(
		component.configure("damage.physical", amount, ability_id),
		"",
		"Enemy fixture damage component must configure."
	)
	var context := DamageContext.new()
	_assert_equal(
		context.configure(
			source_entity_id,
			target_entity_id,
			ability_id,
			origin_event_id,
			PackedStringArray(["damage.physical"]),
			[component],
			[],
			PackedStringArray(),
			0.0,
			1.0,
			1.0
		),
		"",
		"Enemy fixture damage context must configure."
	)
	var resolution: RefCounted = DamagePipeline.resolve(context)
	_assert_true(resolution.is_success(), "Enemy fixture damage must resolve.")
	return resolution.result()


func _kill_events(result: RefCounted) -> Array:
	var values: Array = []
	for event: RefCounted in result.combat_events():
		if event.event_type() == "event.kill":
			values.append(event)
	return values


func _kill_sources(result: RefCounted) -> Array:
	var values: Array = []
	for event: RefCounted in _kill_events(result):
		values.append(event.source_entity_id())
	return values


func _entity_positions(world: RefCounted) -> Array:
	var values: Array = []
	for runtime_id in range(1, 122):
		var position: Vector2 = world.entity_state(runtime_id).position()
		values.append([runtime_id, position.x, position.y])
	return values


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_vector_close(actual: Vector2, expected: Vector2, message: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])
