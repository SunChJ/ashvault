class_name BuildSimulation
extends RefCounted

const Build = preload("res://game/infrastructure/headless/build_loadout.gd")
const Equipment = preload("res://game/simulation/items/equipment_state.gd")
const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const Combat = preload("res://game/simulation/abilities/stormweaver_combat.gd")
const Entity = preload("res://game/simulation/entities/entity_state.gd")
const Movement = preload("res://game/simulation/movement/movement_environment.gd")
const Command = preload("res://game/simulation/commands/player_command.gd")
const Enemy = preload("res://game/simulation/enemies/enemy_definition.gd")
const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const DamageModifier = preload("res://game/simulation/combat/damage_modifier.gd")
const Version = preload("res://game/infrastructure/version_info.gd")
const ARENA_ID := "arena.build_comparison.v1"
const HEALTH := 1000000


static func run(build: Variant, world: Variant, set_bonuses: Array = []) -> Dictionary:
	var resolved := Build.resolve(build, world)
	if not resolved.error.is_empty():
		return resolved
	return _run_slots(build, world, resolved.slots, set_bonuses)


static func compare(build: Variant, world: Variant, set_bonuses: Array = []) -> Dictionary:
	var resolved := Build.resolve(build, world)
	if not resolved.error.is_empty():
		return resolved
	var records: Array = world.snapshot().items
	if records.size() > 64:
		return {"error": "Build comparison supports at most 64 authored candidates."}
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.uid < b.uid)
	var baseline := _run_slots(build, world, resolved.slots, set_bonuses)
	if not baseline.error.is_empty():
		return baseline
	var comparisons: Array = []
	for slot: String in Equipment.SLOTS:
		if not resolved.slots.has(slot):
			continue
		var candidates: Array = []
		var winners: Array = []
		var best := -INF
		for record: Dictionary in records:
			if world.item_catalog().get_definition(record.definition_id).equipment_slot != slot:
				continue
			var slots: Dictionary = resolved.slots.duplicate()
			slots[slot] = record.uid
			var result := _run_slots(build, world, slots, set_bonuses)
			if not result.error.is_empty():
				candidates.append({"item": record, "error": result.error})
				continue
			var metrics: Dictionary = result.report.metrics
			var score: float = metrics.damage_dealt if build.objective == "damage" else (-metrics.damage_taken if build.objective == "defense" else metrics.proc_events)
			candidates.append({"item": record, "error": "", "score": score, "report": result.report})
			if score > best:
				best = score
				winners = [record.uid]
			elif score == best:
				winners.append(record.uid)
		comparisons.append({"slot": slot, "best_score": best, "winners": winners, "candidates": candidates})
	return {"error": "", "report": {"schema_version": 1, "build": build.duplicate(true),
		"baseline": baseline.report, "slots": comparisons, "comparison_scope": "single-slot substitutions against the fixed baseline"}}


static func _run_slots(build: Dictionary, world: RefCounted, slots: Dictionary, set_bonuses: Array) -> Dictionary:
	var registry := Registry.new()
	var definitions: Array = []
	for id: String in Build.STATS:
		var definition := Stat.new()
		var error: String = definition.configure(id, build.base_stats[id])
		if not error.is_empty():
			return {"error": error}
		definitions.append(definition)
	var registry_errors: PackedStringArray = registry.load_definitions(definitions)
	if not registry_errors.is_empty():
		return {"error": str(registry_errors)}
	var gear := Equipment.new()
	var error := gear.configure(world, registry, [], set_bonuses)
	if not error.is_empty():
		return {"error": error}
	var transaction := gear.transact(slots, 0, PackedStringArray(build.conditions))
	if not transaction.error.is_empty():
		return transaction
	var armor := DamageModifier.new()
	error = armor.configure("damage.lightning", DamageModifier.Operation.DEFENSE,
		gear.stats().value("stat.defense.armor"), "source.build.armor")
	if not error.is_empty():
		return {"error": error}
	var ranks: Dictionary = {}
	for skill: String in build.skills:
		ranks[Build.skill_slot(skill)] = int(build.skills[skill])
	var catalog := Catalog.new()
	error = catalog.configure(ranks)
	if not error.is_empty():
		return {"error": error}
	var environment := Movement.new()
	error = environment.configure(Rect2(-500, -500, 1000, 1000), [], 2, 120)
	if not error.is_empty():
		return {"error": error}
	var entities: Array = []
	for id in range(1, 6):
		var entity := Entity.new()
		error = entity.configure(id, "actor.build.e%d" % id, id == 1, Vector2((id - 1) * 50, 0), HEALTH, HEALTH, 10000, 10000)
		if not error.is_empty():
			return {"error": error}
		entities.append(entity)
	var enemy := Enemy.new()
	error = enemy.configure("actor.build.e2", 1000, 1, 2, 1000, 30, "attack.build")
	if not error.is_empty():
		return {"error": error}
	var attack := Ability.new()
	error = attack.configure_ability("ability.build.enemy", [], [], "", 0, 0, 0, 0,
		Ability.Targeting.ENTITY, Ability.Delivery.INSTANT, [Catalog._damage_effect("enemy", 10)], [])
	if not error.is_empty():
		return {"error": error}
	var combat := Combat.new()
	error = combat.configure(entities, environment, catalog, int(build.root_seed), {2: enemy}, {"attack.build": attack}, gear.stats(), [armor])
	if not error.is_empty():
		return {"error": error}
	var batches: Dictionary = {}
	var sequence := 1
	for cast: Dictionary in build.rotation:
		var slot := Build.skill_slot(cast.skill)
		var release_tick: int = int(cast.tick) + int(Catalog.SKILLS[slot].cast)
		if release_tick > int(build.duration_ticks):
			return {"error": "Build cast release falls outside the simulation."}
		for row: Array in [[int(cast.tick), Command.CAST_START], [release_tick, Command.CAST_RELEASE]]:
			var command := Command.new()
			error = command.configure(row[0], 1, row[1], Vector2.RIGHT, slot, sequence)
			if not error.is_empty():
				return {"error": error}
			sequence += 1
			if not batches.has(row[0]):
				batches[row[0]] = []
			batches[row[0]].append(command)
	var metrics := {"damage_dealt": 0, "damage_taken": 0, "hits": 0, "critical_hits": 0, "proc_events": 0, "shock_peak": 0, "ward_ticks": 0}
	var events: Dictionary = {}
	while combat.tick() < int(build.duration_ticks):
		error = combat.advance_tick(batches.get(combat.tick() + 1, []))
		if not error.is_empty():
			return {"error": "Build rotation failed at tick %d: %s" % [combat.tick() + 1, error]}
		var report := combat.report()
		for damage: Array in report.damage:
			if damage[0] == 1:
				metrics.damage_dealt += damage[2]
				metrics.hits += 1
				metrics.critical_hits += int(damage[3])
			if damage[1] == 1:
				metrics.damage_taken += damage[2]
		for event: Array in report.events:
			if event[1] == 1:
				events[event[0]] = events.get(event[0], 0) + 1
				if event[0] == "event.critical":
					metrics.proc_events += 1
		for id in range(2, 6):
			metrics.shock_peak = maxi(metrics.shock_peak, combat.status_stacks(id, Catalog.SHOCK))
			if not combat.entity_state(id).is_alive():
				return {"error": "Comparison target died; shorten the benchmark to avoid censored damage."}
		metrics.ward_ticks += int(combat.status_stacks(1, Catalog.WARD) > 0)
		if not combat.entity_state(1).is_alive():
			return {"error": "Comparison actor died; shorten the benchmark."}
	metrics["dps"] = float(metrics.damage_dealt) * 60.0 / float(build.duration_ticks)
	var composition: Dictionary = {}
	var items: Array = []
	for slot: String in Equipment.SLOTS:
		if slots.has(slot):
			var record: Dictionary = world.get_item(slots[slot]).snapshot()
			items.append({"slot": slot, "item": record})
			composition[record.rarity] = composition.get(record.rarity, 0) + 1
	return {"error": "", "report": {"arena_id": ARENA_ID, "simulation_version": Version.SIMULATION_VERSION,
		"content_version": Version.CONTENT_VERSION, "state_hash": combat.state_hash(),
		"metrics": metrics, "events": events, "stats": gear.stats().values(), "sources": gear.sources(),
		"items": items, "rarities": composition, "special_effects": gear.special_effects(),
		"proc_scope": "player critical-trigger notifications; item-specific proc rules are not implemented"}}
