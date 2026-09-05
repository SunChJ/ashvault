extends SceneTree

const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const Combat = preload("res://game/simulation/abilities/stormweaver_combat.gd")
const Entity = preload("res://game/simulation/entities/entity_state.gd")
const Movement = preload("res://game/simulation/movement/movement_environment.gd")
const Command = preload("res://game/simulation/commands/player_command.gd")
const Enemy = preload("res://game/simulation/enemies/enemy_definition.gd")
const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Component = preload("res://game/simulation/abilities/ability_damage_component.gd")
const Effect = preload("res://game/simulation/abilities/ability_effect_definition.gd")
const Interruption = preload("res://game/simulation/abilities/cast_interruption.gd")
const Transform = preload("res://game/simulation/abilities/ability_effect_transform.gd")

const COMBINED_REPLAY_HASH := "6eb391b4394212ddff516e2e2d9496d48881ac7b3564f15e3e0ec0cff604223c"
const DENSITY_REPLAY_HASH := "8f6b5fca9d01432dbfd9b81d49444316796f14c2405f893a9c97886ae567473e"

var failures: Array[String] = []
var captures: Array = []

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_projectile()
	_test_chain_and_nova()
	_test_totem()
	_test_ward_and_dash()
	_test_cancellation_and_rollback()
	_test_ranks_and_items()
	_test_replay()
	_test_critical_hits_and_shock_cap()
	_test_lethal_hit_suppresses_attack()
	_test_effect_failure_rolls_back()
	_test_density()
	print(JSON.stringify({"fixture": "stormweaver", "captures": captures}))
	if failures.is_empty():
		print("Production Stormweaver ability tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_projectile() -> void:
	var world := _world()
	_cast(world, Catalog.ARC_BOLT)
	_check(world.entity_state(2).health() == 10000, "Projectile must not damage on spawn.")
	_until(world, 9)
	_check(world.entity_state(2).health() < 10000, "Arc Bolt must hit along aim.")
	_check(world.entity_state(3).health() == 10000, "Arc Bolt must stop at its first hit.")
	_capture("arc_bolt", world)
	var miss := _world()
	_cast(miss, Catalog.ARC_BOLT, 1, Vector2.LEFT)
	_until(miss, 65)
	_check(miss.entity_state(2).health() == 10000, "Projectile aimed away must miss.")
	_check(miss.report().active_deliveries == 0, "Missed projectile must expire.")


func _test_chain_and_nova() -> void:
	var world := _world()
	_cast(world, Catalog.CHAIN_LIGHTNING)
	_check(world.report().hits.size() == 4, "Chain must hit four distinct nearby targets.")
	_check(world.status_stacks(2, Catalog.SHOCK) == 1, "Chain must apply Shock.")
	_capture("chain_lightning", world)
	_until(world, 14)
	_cast(world, Catalog.THUNDER_NOVA, 3)
	_check(world.report().hits.size() == 2, "Nova must use player-centered radius.")
	var nova_damage: Array = world.report().damage
	_check(nova_damage[0][2] >= 41, "Shock must amplify the next damage resolution.")
	_capture("thunder_nova_after_shock", world)
	_until(world, 187)
	_check(world.status_stacks(2, Catalog.SHOCK) == 0, "Shock expires at its exclusive end tick.")


func _test_totem() -> void:
	var world := _world()
	_cast(world, Catalog.STORM_TOTEM)
	var first: int = world.entity_state(3).health()
	_check(first < 10000, "Totem must pulse at spawn near its aimed placement.")
	_capture("storm_totem_spawn", world)
	_until(world, 39)
	_check(world.entity_state(3).health() == first, "Totem must not pulse early.")
	_until(world, 40)
	_check(world.entity_state(3).health() < first, "Totem must pulse at its authored interval.")
	_until(world, 189)
	var before_expiry: int = world.entity_state(3).health()
	_until(world, 190)
	_check(world.entity_state(3).health() == before_expiry, "Totem must not pulse at exclusive expiry.")
	_check(world.report().active_deliveries == 0, "Totem must retire at expiry.")


func _test_ward_and_dash() -> void:
	var ward := _world({}, {}, true)
	_cast(ward, Catalog.STATIC_WARD)
	_check(ward.report().damage[0][2] < 15, "Ward must mitigate a same-tick enemy hit.")
	_check(ward.status_stacks(1, Catalog.WARD) == 1, "Ward status must target the player.")
	_capture("static_ward", ward)
	_until(ward, 241)
	_check(ward.status_stacks(1, Catalog.WARD) == 0, "Ward must expire before damage at tick 241.")
	_check(ward.report().damage[0][2] >= 15, "Damage must resume in full at Ward expiry.")
	var dash := _world({}, {}, true)
	_cast(dash, Catalog.TEMPEST_DASH)
	_check(dash.entity_state(1).position().is_equal_approx(Vector2(10, 0)), "Dash starts moving on release tick.")
	_check(dash.entity_state(1).health() == 10000, "Dash must prevent same-tick damage.")
	_until(dash, 12)
	_check(dash.entity_state(1).position().is_equal_approx(Vector2(120, 0)), "Dash must move its exact authored distance.")
	_check(dash.entity_state(1).health() == 10000, "Dash protects every active movement tick.")
	_capture("tempest_dash", dash)
	_until(dash, 13)
	_check(dash.entity_state(1).health() < 10000, "Dash protection must expire at tick 13.")
	_check(dash.entity_state(1).position().is_equal_approx(Vector2(120, 0)), "Dash must stop at expiry.")
	var combined := _world({}, {}, true, [], false, 5, "damage.void")
	_cast(combined, Catalog.STATIC_WARD)
	_until(combined, 5)
	var health_before: int = combined.entity_state(1).health()
	_cast(combined, Catalog.TEMPEST_DASH, 3)
	_check(combined.entity_state(1).health() == health_before, "Dash and Ward must combine correctly for configured non-default damage types.")
	_check(combined.status_stacks(1, Catalog.WARD) == 1, "Dash must preserve an existing Ward.")
	var blocked := _world({}, {}, false, [Rect2(35, -20, 10, 40)])
	_cast(blocked, Catalog.TEMPEST_DASH)
	_until(blocked, 12)
	_check(blocked.entity_state(1).position().x == 33.0, "Dash must stop at the swept obstacle boundary.")


func _test_cancellation_and_rollback() -> void:
	var world := _world()
	_step(world, [_command(1, Command.CAST_START, Catalog.CHAIN_LIGHTNING, 1)])
	_step(world, [_command(2, Command.CAST_START, Catalog.TEMPEST_DASH, 2),
		_command(2, Command.CAST_RELEASE, Catalog.TEMPEST_DASH, 3)])
	_check(world.entity_state(1).resource() == 992.0, "Dash replacement must charge only the committed dash.")
	_check(world.status_stacks(2, Catalog.SHOCK) == 0, "Canceled chain must not publish effects.")
	var before: String = world.state_hash()
	world.presentation_snapshot()
	var external_report: Dictionary = world.report()
	external_report.clear()
	_check(world.state_hash() == before and not world.report().is_empty(), "Presentation reads and report edits must not mutate simulation.")
	var error: String = world.advance_tick([_command(3, Command.CAST_RELEASE, Catalog.CHAIN_LIGHTNING, 4)])
	_check(not error.is_empty(), "Impossible release must be rejected.")
	_check(world.state_hash() == before, "Rejected tick must preserve all world and RNG state.")
	_check(world.tick() == 2, "Rejected tick must not advance time.")
	var interrupted := _world({}, {}, true)
	_cast(interrupted, Catalog.TEMPEST_DASH)
	var position: Vector2 = interrupted.entity_state(1).position()
	var interruption := Interruption.new()
	_check(interruption.configure(1, "interrupt.stun").is_empty(), "Interruption must configure.")
	_check(interrupted.advance_tick([], [interruption]).is_empty(), "Dash interruption must commit.")
	_check(interrupted.entity_state(1).position() == position, "Interrupted dash must stop moving immediately.")
	_check(interrupted.status_stacks(1, Catalog.INVULNERABLE) == 0, "Interrupted dash must remove protection.")
	_check(interrupted.entity_state(1).health() < 10000, "Interrupted dash must allow same-tick enemy damage.")
	var early := _world()
	_step(early, [_command(1, Command.CAST_START, Catalog.ARC_BOLT, 1)])
	before = early.state_hash()
	_check(not early.advance_tick([_command(2, Command.CAST_RELEASE, Catalog.ARC_BOLT, 2)]).is_empty(), "Early release must fail.")
	_check(early.state_hash() == before, "Early release must preserve resources and cooldowns.")


func _test_ranks_and_items() -> void:
	var base := _world()
	var ranked := _world({Catalog.THUNDER_NOVA: 5})
	_check(base.state_hash() != ranked.state_hash(), "Content rank must participate in the initial replay hash.")
	_cast(base, Catalog.THUNDER_NOVA)
	_cast(ranked, Catalog.THUNDER_NOVA)
	_check(ranked.entity_state(2).health() < base.entity_state(2).health(), "Rank milestone must increase Nova damage.")
	var transform := Transform.new()
	_check(transform.configure("source.item.fixture", "effect.thunder_nova.damage",
		Catalog._damage_effect("thunder_nova", 100.0)).is_empty(), "Item fixture transform must configure.")
	var item_world := _world({}, {Catalog.THUNDER_NOVA: [transform]})
	_cast(item_world, Catalog.THUNDER_NOVA)
	_check(item_world.entity_state(2).health() < ranked.entity_state(2).health(), "Item damage must reach the shared pipeline.")
	_check(item_world.entity_state(1).resource() == base.entity_state(1).resource(), "Item transform must preserve cast costs.")
	var catalog := Catalog.new()
	_check(not catalog.configure({}, {Catalog.STATIC_WARD: [transform]}).is_empty(), "Invalid transform targets must be rejected.")
	_check(not catalog.configure({0: 0}).is_empty(), "Rank zero must be rejected.")
	var ranked_dash := _world({Catalog.TEMPEST_DASH: 5})
	_cast(ranked_dash, Catalog.TEMPEST_DASH)
	_until(ranked_dash, 12)
	_check(is_equal_approx(ranked_dash.entity_state(1).position().x, 180.0), "Dash rank transform must change swept movement distance.")


func _test_replay() -> void:
	var left := _world()
	var right := _world({}, {}, false, [], true)
	for world in [left, right]:
		_cast(world, Catalog.CHAIN_LIGHTNING)
		_until(world, 14)
		_cast(world, Catalog.STORM_TOTEM, 3)
		_until(world, 31)
		_cast(world, Catalog.ARC_BOLT, 5)
		_until(world, 120)
	_check(left.state_hash() == right.state_hash(), "Reordered entity input must replay identically.")
	_check(left.report() == right.report(), "Reordered replay evidence must be identical.")
	var normal_dash := _world()
	var reversed_dash := _world()
	_cast(normal_dash, Catalog.TEMPEST_DASH)
	_step(reversed_dash, [_command(1, Command.CAST_RELEASE, Catalog.TEMPEST_DASH, 2),
		_command(1, Command.CAST_START, Catalog.TEMPEST_DASH, 1)])
	_check(normal_dash.state_hash() == reversed_dash.state_hash(), "Command collection order must not change cast execution.")
	_check(left.state_hash() == COMBINED_REPLAY_HASH, "Combined replay hash differs from the shared desktop fixture.")
	_capture("combined_replay", left)


func _test_critical_hits_and_shock_cap() -> void:
	var projectile := _world()
	var critical_count := 0
	for index in 30:
		_cast(projectile, Catalog.ARC_BOLT, index * 2 + 1)
		_until(projectile, projectile.tick() + 5)
		for damage: Array in projectile.report().damage:
			if damage[3]:
				critical_count += 1
		_until(projectile, projectile.tick() + 12)
	_check(critical_count > 0, "Seeded Arc Bolt fixture must exercise the critical damage path.")
	var shock := _world()
	for index in 4:
		_cast(shock, Catalog.CHAIN_LIGHTNING, index * 2 + 1)
		if index < 3:
			_until(shock, shock.tick() + 60)
	_check(shock.status_stacks(2, Catalog.SHOCK) == 3, "Repeated chains must respect the three-stack Shock cap.")
	_capture("shock_stack_cap", shock)


func _test_lethal_hit_suppresses_attack() -> void:
	var transform := Transform.new()
	_check(transform.configure("source.item.lethal", "effect.thunder_nova.damage",
		Catalog._damage_effect("thunder_nova", 20000.0)).is_empty(), "Lethal transform must configure.")
	var world := _world({}, {Catalog.THUNDER_NOVA: [transform]}, true)
	_cast(world, Catalog.THUNDER_NOVA)
	_check(world.entity_state(2).health() == 0, "Lethal ability must commit enemy death.")
	for record: Array in world.report().damage:
		_check(record[0] == 1, "Enemy killed before its decision must not attack.")
	var kills := 0
	for event: Array in world.report().events:
		if event[0] == "event.kill":
			kills += 1
	_check(kills == 2, "Nova must publish exactly one kill per defeated target.")


func _test_effect_failure_rolls_back() -> void:
	var component := Component.new()
	_check(component.configure("damage.lightning", 20.0, "stat.missing", 1.0, "source.fixture.missing").is_empty(), "Missing-stat fixture component must configure.")
	var effect := Effect.new()
	_check(effect.configure_damage("effect.thunder_nova.damage", [], [], [component], []).is_empty(), "Missing-stat effect graph must configure.")
	var transform := Transform.new()
	_check(transform.configure("source.item.missing", effect.effect_id(), effect).is_empty(), "Missing-stat transform must configure.")
	var world := _world({}, {Catalog.THUNDER_NOVA: [transform]})
	_step(world, [_command(1, Command.CAST_START, Catalog.THUNDER_NOVA, 1)])
	_until(world, 6)
	var before: String = world.state_hash()
	var report_before: Dictionary = world.report()
	var error: String = world.advance_tick([_command(7, Command.CAST_RELEASE, Catalog.THUNDER_NOVA, 2)])
	_check(error.contains("Missing scaling stat"), "Late effect failure must retain its actionable diagnostic.")
	_check(world.state_hash() == before and world.report() == report_before, "Effect failure must roll back cost, delivery, RNG, events, and report.")
	_step(world, [_command(7, Command.CANCEL, -1, 2, Vector2.ZERO)])
	_check(world.entity_state(1).resource() == 1000.0, "Failed effect must not consume mana.")


func _test_density() -> void:
	var left := _world({}, {}, true, [], false, 121)
	var right := _world({}, {}, true, [], true, 121)
	for world in [left, right]:
		_cast(world, Catalog.TEMPEST_DASH)
		_until(world, 15)
		_cast(world, Catalog.THUNDER_NOVA, 3)
		_until(world, 30)
	_check(left.state_hash() == right.state_hash(), "120-enemy combat must replay independently of input order.")
	_check(left.report().damage.size() == 120, "Density fixture must resolve all 120 enemy attack intents.")
	_check(left.state_hash() == DENSITY_REPLAY_HASH, "Density replay hash differs from the shared desktop fixture.")
	_capture("density_120", left)


func _world(ranks: Dictionary = {}, transforms: Dictionary = {}, attackers: bool = false,
	obstacles: Array = [], reverse_entities: bool = false, entity_count: int = 5, enemy_damage_type: String = "damage.lightning") -> RefCounted:
	var catalog := Catalog.new()
	_check(catalog.configure(ranks, transforms).is_empty(), "Catalog must configure.")
	var environment := Movement.new()
	_check(environment.configure(Rect2(-500, -500, 1000, 1000), obstacles, 2.0, 120.0).is_empty(), "Environment must configure.")
	var entities: Array = []
	for id in range(1, entity_count + 1):
		var entity := Entity.new()
		var position := Vector2(float(id - 1) * 50, 0)
		if entity_count > 5 and id > 1:
			position = Vector2(50 + ((id - 2) % 12) * 20, floori(float(id - 2) / 12) * 20)
		var health := 1000000 if entity_count > 5 else 10000
		_check(entity.configure(id, "actor.fixture.e%d" % id, id == 1, position, health, health, 1000.0, 1000.0).is_empty(), "Entity must configure.")
		entities.append(entity)
	if reverse_entities:
		entities.reverse()
	var definitions: Dictionary = {}
	var attacks: Dictionary = {}
	if attackers:
		for id in range(2, entity_count + 1 if entity_count > 5 else 3):
			var enemy := Enemy.new()
			_check(enemy.configure("actor.fixture.e%d" % id, 1000.0, 1.0, 2.0, 1000.0, 1, "attack.fixture").is_empty(), "Enemy must configure.")
			definitions[id] = enemy
		var attack_effect := Catalog._damage_effect("enemy", 10.0)
		if enemy_damage_type != "damage.lightning":
			var component := Component.new()
			_check(component.configure(enemy_damage_type, 10.0, Catalog.POWER, 0.5, "source.fixture.enemy").is_empty(), "Custom enemy component must configure.")
			attack_effect = Effect.new()
			_check(attack_effect.configure_damage("effect.enemy.damage", [], [], [component], []).is_empty(), "Custom enemy damage must configure.")
		var ability := Ability.new()
		_check(ability.configure_ability("ability.fixture.enemy", [], [], "", 0, 0, 0, 0,
			Ability.Targeting.ENTITY, Ability.Delivery.INSTANT, [attack_effect], []).is_empty(), "Enemy attack must configure.")
		attacks["attack.fixture"] = ability
	var world := Combat.new()
	_check(world.configure(entities, environment, catalog, 42, definitions, attacks).is_empty(), "Combat must configure.")
	return world


func _cast(world: RefCounted, slot: int, sequence: int = 1, direction: Vector2 = Vector2.RIGHT) -> void:
	var start_tick: int = world.tick() + 1
	var ready_tick: int = start_tick + Catalog.SKILLS[slot].cast
	var commands: Array = [_command(start_tick, Command.CAST_START, slot, sequence, direction)]
	if ready_tick == start_tick:
		commands.append(_command(start_tick, Command.CAST_RELEASE, slot, sequence + 1, direction))
	_step(world, commands)
	if ready_tick > start_tick:
		_until(world, ready_tick - 1)
		_step(world, [_command(ready_tick, Command.CAST_RELEASE, slot, sequence + 1, direction)])


func _until(world: RefCounted, tick_value: int) -> void:
	while world.tick() < tick_value:
		if not _step(world):
			return


func _step(world: RefCounted, commands: Array = []) -> bool:
	var error: String = world.advance_tick(commands)
	_check(error.is_empty(), "Combat tick failed: %s" % error)
	return error.is_empty()


func _command(tick_value: int, type: String, slot: int, sequence: int, direction: Vector2 = Vector2.RIGHT) -> RefCounted:
	var command := Command.new()
	_check(command.configure(tick_value, 1, type, direction, slot, sequence).is_empty(), "Command must configure.")
	return command


func _capture(name: String, world: RefCounted) -> void:
	captures.append({"ability": name, "report": world.report()})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
