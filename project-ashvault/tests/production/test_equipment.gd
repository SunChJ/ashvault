extends SceneTree

const Fixture = preload("res://tests/fixtures/items/equipment_fixture.gd")
const Equipment = preload("res://game/simulation/items/equipment_state.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture: Dictionary = Fixture.create()
	var gear := Equipment.new()
	_check(gear.configure(fixture.world, fixture.registry, [], fixture.set_bonuses).is_empty(), "Equipment must configure.")
	var all_slots: Dictionary = {}
	for slot: String in Equipment.SLOTS:
		all_slots[slot] = fixture.items[slot].uid()
	var world_before: Dictionary = fixture.world.snapshot()
	var equipped: Dictionary = gear.transact(all_slots, 1)
	_check(equipped.error.is_empty(), "All eight compatible slots must equip together.")
	_check(gear.snapshot().slots.size() == 8 and gear.stats().value("stat.power") == 123.0, "Base, affix, and 2/3/4-piece set contributions must aggregate.")
	_check(gear.stats().explanation("stat.power").applied_sources.size() == 16, "Explanations must include every equipped base, affix, and set threshold.")
	for source: Dictionary in gear.stats().explanation("stat.power").applied_sources:
		_check(gear.sources().has(source.source_id), "Every equipped contribution must trace to an item or set source.")
	var old: RefCounted = gear.stats()
	var state: Dictionary = gear.snapshot()
	var exposed: Dictionary = gear.snapshot()
	exposed.slots["slot.weapon"] = ""
	_check(gear.snapshot() == state, "Equipment snapshots must not alias live slots.")
	for invalid: Dictionary in [{"slot.unknown": ""}, {"slot.head": fixture.items["slot.weapon"].uid()}, {"slot.weapon": "profile.foreign:1"}, {"slot.weapon": fixture.two_handed.uid()}, {"slot.weapon": fixture.invalid_stat.uid()}, {"slot.head": 123}, {"slot.off_hand": fixture.items["slot.weapon"].uid()}]:
		_check(not gear.transact(invalid, 2).error.is_empty(), "Invalid equip transaction must fail.")
		_check(gear.snapshot() == state and gear.stats() == old, "Failed equip must retain both slots and stat snapshot.")
	_check(fixture.world.snapshot() == world_before, "Equip transactions must not rewrite item identities or records.")
	var swapped: Dictionary = gear.transact({"slot.weapon": fixture.two_handed.uid(), "slot.off_hand": ""}, 2)
	_check(swapped.error.is_empty() and swapped.displaced.size() == 2, "Atomic two-hand swap must report both displaced items.")
	_check(gear.stats().explanation("stat.power").skipped_sources.size() == 1, "Inactive equipment conditions must remain in explanations.")
	_check(gear.stats().value("stat.power") == 129.0 and old.value("stat.power") == 123.0, "Replacement must recompute without changing old snapshots.")
	_check(not gear.transact({"slot.off_hand": fixture.items["slot.off_hand"].uid()}, 3).error.is_empty(), "Off-hand cannot equip while a two-handed weapon remains.")
	var other := Equipment.new()
	other.configure(fixture.world, fixture.registry, [], fixture.set_bonuses)
	other.transact(all_slots, 1)
	_check(other.transact({"slot.off_hand": "", "slot.weapon": fixture.two_handed.uid()}, 2).error.is_empty(), "Batch validation must not depend on dictionary order.")
	_check(other.snapshot() == gear.snapshot() and other.stats().values() == gear.stats().values(), "Equivalent swaps must publish equivalent states.")
	var restored := Equipment.new()
	restored.configure(fixture.world, fixture.registry, [], fixture.set_bonuses)
	_check(restored.restore(JSON.parse_string(JSON.stringify(gear.snapshot())), 2).error.is_empty(), "Equipment DTO must round-trip through JSON.")
	_check(restored.stats().values() == gear.stats().values(), "Restore must recompute identical aggregate stats.")
	var saved: Dictionary = gear.snapshot()
	saved.slots.erase("slot.head")
	_check(not restored.restore(saved, 3).error.is_empty(), "Restore must require exactly eight slots.")
	_check(not gear.transact({}, 1).error.is_empty(), "Equipment stat ticks must not move backwards.")
	_check(gear.transact({}, 3, PackedStringArray(["condition.empowered"])).error.is_empty(), "Condition refresh must resolve through the shared system.")
	_check(gear.stats().value("stat.power") == 258.0, "Conditional MORE must multiply the shared aggregate.")
	_check(gear.transact({"slot.feet": ""}, 4).error.is_empty() and gear.stats().value("stat.power") == 123.0, "Dropping to three set pieces must remove only the four-piece bonus and unequipped stats.")
	_check(gear.transact({"slot.hands": ""}, 5).error.is_empty() and gear.stats().value("stat.power") == 118.0, "Dropping to two pieces must remove the three-piece bonus.")
	_check(gear.transact({"slot.body": ""}, 6).error.is_empty() and gear.stats().value("stat.power") == 114.0, "Dropping to one piece must remove all set bonuses.")
	Fixture.test_validation(failures)
	Fixture.test_operations(failures)
	var duplicate_source := Fixture.Modifier.new()
	duplicate_source.configure("stat.power", Fixture.Modifier.Operation.FLAT, 1, "equipment.profile.gear.i1.affix.power")
	var conflicting := Equipment.new()
	_check(conflicting.configure(fixture.world, fixture.registry, [duplicate_source], fixture.set_bonuses).is_empty(), "Baseline modifier must configure before item-source collision.")
	var before_collision: RefCounted = conflicting.stats()
	_check(not conflicting.transact({"slot.weapon": fixture.items["slot.weapon"].uid()}, 1).error.is_empty() and conflicting.stats() == before_collision, "Duplicate modifier identity must roll back the equip transaction.")
	var no_sets := Equipment.new()
	no_sets.configure(fixture.world, fixture.registry)
	_check(not no_sets.transact({"slot.head": fixture.items["slot.head"].uid()}, 1).error.is_empty(), "Set items must not silently ignore unregistered bonuses.")
	var special := Equipment.new()
	special.configure(fixture.world, fixture.registry)
	_check(special.transact({"slot.weapon": fixture.special.uid()}, 1).error.is_empty(), "Rule-bearing item must still contribute through shared stats.")
	_check(special.special_effects() == [{"uid": fixture.special.uid(), "interaction_id": "", "rule_id": "rule.fixture"}], "Special effect declarations must retain explicit item provenance.")
	var declarations: Array = special.special_effects()
	declarations[0].rule_id = "rule.changed"
	_check(special.special_effects()[0].rule_id == "rule.fixture", "Special effect declarations must be defensive copies.")
	special.transact({"slot.weapon": ""}, 2)
	_check(special.special_effects().is_empty(), "Unequipping must retire special effect declarations.")
	fixture.set_bonuses[0].effects[0].amount = 999
	_check(fixture.set_bonuses[0].effects[0].amount == 2, "Published set bonus effects must remain frozen.")
	print(JSON.stringify({"fixture": "equipment", "slots": gear.snapshot().slots, "stats": gear.stats().values()}))
	if failures.is_empty():
		print("Production equipment contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
