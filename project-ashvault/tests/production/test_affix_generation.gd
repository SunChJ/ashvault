extends SceneTree

const Fixture = preload("res://tests/fixtures/items/affix_fixture.gd")
const Generator = preload("res://game/simulation/items/item_generator.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const REPLAY_DIGEST := "2f5c65bf791cb5ac06fb0df9ef0e2a3f1ed9c08c5e6a287d6d3babe82df0aa55"
const Rules = preload("res://game/simulation/items/rarity_rules.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: RefCounted = Fixture.catalog()
	var world := World.new()
	_check(world.configure("profile.affixes", catalog).is_empty(), "World must configure.")
	var rng := Streams.new()
	rng.initialize(424242)
	var initial: Dictionary = rng.snapshot()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var observed: Dictionary = {}
	for index in 7000:
		var rarity: String = Rules.RARITIES[index % 7]
		var level: int = [1, 10, 20, 30, 40][(index / 7) % 5]
		var result: Dictionary = Generator.generate(world, rng, Fixture.item_id(rarity, index), level, rarity)
		_check(result.error.is_empty(), "Generation must succeed: %s" % result.error)
		if not result.error.is_empty():
			break
		var record: Dictionary = result.item.snapshot()
		_check(catalog.validate_record(record).is_empty(), "Generated item must satisfy all constraints.")
		_check(record.rarity == rarity and record.item_level == level, "Generator must preserve the request.")
		var count: int = record.affixes.size()
		match rarity:
			"white": _check(count == 0, "White bases must have no affixes.")
			"blue": _check(count >= 1 and count <= 2, "Blue generation must stay within two affixes.")
			"gold": _check(count >= 1 and count <= 4, "Gold generation must stay within four affixes.")
			"green": _check(record.affixes.has("affix.implicit") and count >= 3 and count <= 4, "Green must retain its implicit plus two or three random affixes.")
			"purple": _check(record.affixes.has("affix.implicit") and count >= 2 and count <= 3, "Purple must retain its authored interaction affix and bounded random affixes.")
			"red", "set": _check(record.affixes == ["affix.implicit"], "Red/set must retain fixed affixes without extra budget.")
		_check(not (record.affixes.has("affix.power") and record.affixes.has("affix.speed")), "One-sided exclusions must prevent both orderings.")
		_check(not (record.affixes.has("affix.power") and record.affixes.has("affix.power_alt")), "Affix groups must be unique.")
		for roll: Dictionary in record.rolls:
			_check(roll.tier == 1 or level >= (roll.tier - 1) * 10, "Generated tiers must respect item level.")
			_check(roll.value >= roll.tier * 2 and roll.value <= roll.tier * 2 + 1, "Roll values must stay inside authored bounds.")
			observed["%s:%d" % [rarity, roll.tier]] = true
		digest.update(JSON.stringify(record, "", true, true).to_utf8_buffer())
	var hash_value := digest.finish().hex_encode()
	_check(hash_value == REPLAY_DIGEST, "Seeded replay must match the shared desktop digest.")
	_check(observed.has("blue:5") and not observed.has("gold:5"), "Blue must have the higher individual tier ceiling.")
	_check(Rules.targeted_reroll_weight("blue") < Rules.targeted_reroll_weight("gold"), "Blue must have cheaper targeted rerolls.")
	_check(rng.snapshot().streams.combat == initial.streams.combat and rng.snapshot().streams.dungeon == initial.streams.dungeon, "Only loot RNG may advance.")
	_test_replay(catalog)
	_test_failures(catalog)
	_test_backtracking(catalog)
	Fixture.test_publication(failures)
	print(JSON.stringify({"fixture": "affix_generation", "samples": world.snapshot().items.size(), "digest": hash_value}))
	if failures.is_empty():
		print("Production affix generation contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_replay(catalog: RefCounted) -> void:
	var left := World.new()
	left.configure("profile.replay", catalog)
	var right := World.new()
	right.configure("profile.replay", Fixture.catalog(true))
	var a := Streams.new()
	var b := Streams.new()
	a.initialize(17)
	b.initialize(17)
	for index in 70:
		var rarity: String = Rules.RARITIES[index % 7]
		var first: Dictionary = Generator.generate(left, a, Fixture.item_id(rarity), 40, rarity)
		var second: Dictionary = Generator.generate(right, b, Fixture.item_id(rarity), 40, rarity)
		_check(first.item.snapshot() == second.item.snapshot(), "Seed replay must ignore catalog insertion order.")
	var resumed := World.new()
	resumed.configure("profile.replay", catalog)
	_check(resumed.restore(JSON.parse_string(JSON.stringify(left.snapshot(), "", true, true))).is_empty(), "Generated items must restore.")
	var resumed_rng := Streams.new()
	_check(resumed_rng.restore(JSON.parse_string(JSON.stringify(a.snapshot()))).is_empty(), "Loot RNG must restore.")
	_check(Generator.generate(left, a, "item.base", 40, "gold").item.snapshot() == Generator.generate(resumed, resumed_rng, "item.base", 40, "gold").item.snapshot(), "Save continuation must reproduce the next item exactly.")


func _test_failures(catalog: RefCounted) -> void:
	var world := World.new()
	world.configure("profile.failures", catalog)
	var rng := Streams.new()
	rng.initialize(4)
	var baseline: Dictionary = world.snapshot()
	var rng_before: Dictionary = rng.snapshot()
	for request: Array in [["item.missing", 40, "gold"], ["item.base", 0, "gold"], ["item.base", 1.5, "blue"], ["item.base", 40, "green"], ["item.base", 40, "unknown"], ["item.blocked", 40, "green"]]:
		_check(not Generator.generate(world, rng, request[0], request[1], request[2]).error.is_empty(), "Illegal generation request must fail.")
	_check(world.snapshot() == baseline and rng.snapshot() == rng_before, "Failed generation must consume neither UID nor RNG.")
	var exhausted := World.new()
	exhausted.configure("profile.exhausted", catalog)
	var terminal: Dictionary = exhausted.snapshot()
	terminal.next_sequence = "9223372036854775807"
	_check(exhausted.restore(terminal).is_empty(), "Exhausted allocator must restore.")
	_check(not Generator.generate(exhausted, rng, "item.base", 40, "gold").error.is_empty(), "Generation must fail when UID allocation is exhausted.")
	_check(rng.snapshot() == rng_before and exhausted.snapshot() == terminal, "Post-selection UID failure must not commit loot RNG.")
	var valid: Dictionary = Generator.generate(world, rng, "item.base", 40, "blue").item.snapshot()
	for mutation: String in ["unknown", "missing_roll", "duplicate_group", "excluded", "slot", "base", "level", "tier", "bounds", "rarity", "count"]:
		var record: Dictionary = Fixture.illegal_record(valid, mutation)
		_check(not catalog.validate_record(record).is_empty(), "Illegal combination must be rejected: %s" % mutation)
		var fields: Dictionary = record.duplicate(true)
		fields.erase("uid")
		fields.erase("definition_id")
		var before: Dictionary = world.snapshot()
		_check(not world.create_item(record.definition_id, fields).error.is_empty() and world.snapshot() == before, "Manual creation must enforce the same legality without consuming IDs.")
		var saved: Dictionary = world.snapshot()
		saved.items = [record]
		var target := World.new()
		target.configure("profile.failures", catalog)
		_check(not target.restore(saved).is_empty() and target.snapshot().items.is_empty(), "Restore must enforce affix legality atomically.")


func _test_backtracking(catalog: RefCounted) -> void:
	var world := World.new()
	world.configure("profile.trap", catalog)
	var rng := Streams.new()
	rng.initialize(101)
	for index in 64:
		var result: Dictionary = Generator.generate(world, rng, "item.trap", 40, "green")
		_check(result.error.is_empty(), "Backtracking must recover from a candidate that excludes all alternatives.")
		if not result.error.is_empty():
			break
		var record: Dictionary = result.item.snapshot()
		_check(record.affixes.size() == 3 and record.affixes.has("affix.trap_a") and record.affixes.has("affix.trap_b"), "Search must find the feasible pair and fall back from an impossible count of three.")
	for rarity: String in ["green", "purple", "red", "set"]:
		var record: Dictionary = Generator.generate(world, rng, Fixture.item_id(rarity), 40, rarity).item.snapshot()
		record.affixes.erase("affix.implicit")
		record.rolls = record.rolls.filter(func(roll: Dictionary) -> bool: return roll.affix_id != "affix.implicit")
		_check(not catalog.validate_record(record).is_empty(), "Special item must retain its mandatory affix.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
