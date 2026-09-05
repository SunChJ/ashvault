extends SceneTree

const Fixture = preload("res://tests/fixtures/items/crafting_fixture.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Ownership = preload("res://game/simulation/items/inventory_state.gd")
const AUTH := "authority.local"
const OWNER := "actor.player"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _capture(f: Dictionary) -> Array:
	return [f.world.snapshot(), f.inventory.snapshot(), f.streams.snapshot()]


func _craft(f: Dictionary, slot: int, recipe: String, target: String = "") -> Dictionary:
	return f.inventory.craft(AUTH, OWNER, slot, f.world.get_item(f.items[slot].uid()), recipe, f.streams, target)


func _grant(f: Dictionary) -> void:
	_check(f.inventory.grant_materials(AUTH, OWNER, {"material.shard": 1000, "rune.spark": 5, "rune.tide": 5}).is_empty(), "Known material grant must succeed.")


func _run() -> void:
	var f: Dictionary = Fixture.create()
	var before: Array = _capture(f)
	_check(not _craft(f, 0, "quality").error.is_empty(), "Insufficient shards must fail.")
	_check(not _craft(f, 1, "reroll", "affix.power").error.is_empty(), "Insufficient reroll materials must fail after staged RNG draw.")
	_check(_capture(f) == before, "Failed recipes must preserve items, locations, materials, and RNG.")
	_grant(f)
	before = _capture(f)
	for args: Array in [[0, "unknown", ""], [1, "socket", ""], [0, "reroll", "affix.power"], [1, "reroll", "affix.unknown"], [4, "reroll", "affix.power"], [0, "insert_rune", "rune.spark"], [0, "quality", "unexpected"]]:
		_check(not _craft(f, args[0], args[1], args[2]).error.is_empty(), "Illegal recipe or target must fail.")
	_check(not f.inventory.craft("authority.foreign", OWNER, 0, f.items[0], "quality", f.streams).error.is_empty(), "Foreign creator must reject crafting.")
	_check(not f.inventory.craft(AUTH, "actor.foreign", 0, f.items[0], "quality", f.streams).error.is_empty(), "Foreign owner must reject crafting.")
	_check(_capture(f) == before, "Illegal recipes must preserve all state.")
	var original: RefCounted = f.items[0]
	_check(_craft(f, 0, "quality").error.is_empty(), "Quality recipe must succeed.")
	_check(original.snapshot().quality == 0 and f.world.get_item(original.uid()).snapshot().quality == 1, "Replacement must retain UID and preserve the old immutable reference.")
	before = _capture(f)
	_check(not f.inventory.craft(AUTH, OWNER, 0, original, "quality", f.streams).error.is_empty(), "Stale item references must not repeat a recipe.")
	_check(_capture(f) == before, "Stale recipe must not charge materials.")
	_check(_craft(f, 0, "socket").costs["material.shard"] == 5, "First white socket must use policy cost.")
	_check(_craft(f, 0, "socket").costs["material.shard"] == 10, "Second white socket must use increasing cost.")
	before = _capture(f)
	_check(not _craft(f, 0, "socket").error.is_empty(), "Socket capacity must be enforced.")
	_check(not _craft(f, 0, "insert_rune", "rune.unknown").error.is_empty(), "Unpublished runes must reject insertion.")
	_check(_capture(f) == before, "Rejected socket operations must roll back.")
	_check(_craft(f, 0, "insert_rune", "rune.spark").runeword_id.is_empty(), "Partial sequences must not activate a word.")
	_check(_craft(f, 0, "insert_rune", "rune.tide").runeword_id == "runeword.storm", "Exact ordered runes on a white eligible base must activate.")
	_check(f.inventory.equip(AUTH, OWNER, {"slot.weapon": original.uid()}, 1).is_empty(), "Crafted item must equip through the owned wrapper.")
	_check(is_equal_approx(f.inventory.equipment_stats(OWNER).value("stat.power"), 120.1), "Quality, individual runes, and word effects must aggregate through shared stats.")
	before = _capture(f)
	_check(not _craft(f, 0, "salvage").error.is_empty(), "Equipped items cannot be salvaged.")
	_check(_capture(f) == before, "Equipped target rejection must preserve stats and ownership.")
	_check(f.inventory.equip(AUTH, OWNER, {"slot.weapon": ""}, 2).is_empty(), "Crafted item must unequip normally.")
	for _index in 19:
		_check(_craft(f, 0, "quality").error.is_empty(), "Quality upgrades must reach their cap.")
	before = _capture(f)
	_check(not _craft(f, 0, "quality").error.is_empty() and _capture(f) == before, "Quality cap must reject further charges.")
	var salvage: Dictionary = _craft(f, 0, "salvage")
	_check(salvage.error.is_empty() and salvage.yields["material.shard"] == 1, "White salvage yield must follow policy.")
	_check(f.inventory.location(original.uid()).container == "consumed", "Salvage must retire the UID location.")
	before = _capture(f)
	_check(not _craft(f, 0, "salvage").error.is_empty(), "Duplicate salvage must reject.")
	_check(not f.inventory.place_item(AUTH, OWNER, "bag", 0, original.uid()).is_empty(), "Consumed UIDs cannot be reclaimed through setup.")
	_check(_capture(f) == before, "Repeated salvage must not grant materials.")
	_test_rerolls()
	_test_words_and_validation()
	_test_material_overflow()
	_test_recipe_boundaries()
	print(JSON.stringify({"fixture": "crafting", "quality_cap": 20, "materials": f.inventory.snapshot().owners[OWNER].materials}))
	if failures.is_empty():
		print("Production crafting contracts passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_rerolls() -> void:
	var a: Dictionary = Fixture.create()
	var b: Dictionary = Fixture.create()
	_grant(a)
	_grant(b)
	var rng_before: Dictionary = a.streams.snapshot()
	for _index in 20:
		var first: Dictionary = _craft(a, 1, "reroll", "affix.power")
		var second: Dictionary = _craft(b, 1, "reroll", "affix.power")
		_check(first == second and first.error.is_empty() and first.costs["material.shard"] == 10, "Seeded blue rerolls must reproduce and use the cheapest cost.")
		_check(_capture(a) == _capture(b), "Repeated seeded crafting must preserve deterministic state.")
	var record: Dictionary = a.world.get_item(a.items[1].uid()).snapshot()
	_check(record.rolls[0].tier == 2 and record.rolls[0].value >= 3 and record.rolls[0].value <= 4 and record.affixes == ["affix.power"], "Targeted rerolls must preserve affix and tier legality.")
	_check(_craft(a, 2, "reroll", "affix.power").costs["material.shard"] == 20, "Gold targeted reroll must cost twice blue.")
	_check(a.streams.snapshot().streams.combat == rng_before.streams.combat and a.streams.snapshot().streams.dungeon == rng_before.streams.dungeon, "Only loot RNG may advance.")
	_check(is_equal_approx(record.rolls[0].value, 3.550166), "Seeded reroll must retain its pinned value.")
	print(JSON.stringify({"fixture": "seeded_reroll", "value": record.rolls[0].value}))


func _test_words_and_validation() -> void:
	var f: Dictionary = Fixture.create()
	_grant(f)
	for slot: int in [0, 3]:
		_craft(f, slot, "socket")
		_craft(f, slot, "socket")
	_craft(f, 0, "insert_rune", "rune.tide")
	_check(_craft(f, 0, "insert_rune", "rune.spark").runeword_id.is_empty(), "Reversed rune order must not activate a word.")
	_craft(f, 3, "insert_rune", "rune.spark")
	_check(_craft(f, 3, "insert_rune", "rune.tide").runeword_id.is_empty(), "Ineligible base must not activate a word.")
	var blue: Dictionary = f.world.get_item(f.items[1].uid()).snapshot()
	blue.sockets = ["rune.spark", "rune.tide"]
	_check(f.crafting.active_word(blue) == null, "Non-white rarity cannot activate runewords.")
	var old: RefCounted = f.world.get_item(f.items[0].uid())
	var before: Array = _capture(f)
	for mutation: Dictionary in [{"quality": 21}, {"sockets": ["rune.unknown"]}, {"uid": "profile.foreign:1"}, {"definition_id": "item.other"}]:
		var record: Dictionary = old.snapshot()
		record.merge(mutation, true)
		_check(not f.world.replace_item(old, record).error.is_empty(), "Invalid replacement must fail validation.")
	_check(_capture(f) == before, "Invalid record replacement must be atomic.")
	var restored := World.new()
	restored.configure("profile.craft", f.world.item_catalog())
	_check(restored.restore(JSON.parse_string(JSON.stringify(f.world.snapshot(), "", true, true))).is_empty(), "Crafted records must restore through catalog validation.")
	var reversed: Array[String] = ["rune.tide", "rune.spark"]
	f.word.runes = reversed
	f.tide.effects[0].amount = 999
	f.crafting.policy().reroll_rate = 999
	_check(f.word.runes == ["rune.spark", "rune.tide"] and f.tide.effects[0].amount == 3 and f.crafting.policy().reroll_rate == 10, "Published recipes and nested effects must freeze.")


func _test_material_overflow() -> void:
	var f: Dictionary = Fixture.create()
	_check(f.inventory.grant_materials(AUTH, OWNER, {"material.shard": Ownership.MAX_CURRENCY}).is_empty(), "Material cap fixture must initialize.")
	var before: Array = _capture(f)
	_check(not _craft(f, 0, "salvage").error.is_empty(), "Overflowing salvage yield must reject without consuming the item.")
	for amounts: Dictionary in [{"material.shard": 1}, {"material.unknown": 1}, {"rune.spark": -1}, {"rune.spark": 1.5}]:
		_check(not f.inventory.grant_materials(AUTH, OWNER, amounts).is_empty(), "Invalid or overflowing material grants must reject.")
	_check(_capture(f) == before, "Material failures must preserve every balance and item.")


func _test_recipe_boundaries() -> void:
	var f: Dictionary = Fixture.create()
	f.inventory.grant_materials(AUTH, OWNER, {"material.shard": 100})
	_craft(f, 0, "socket")
	var before: Array = _capture(f)
	_check(not _craft(f, 0, "insert_rune", "rune.spark").error.is_empty(), "Missing rune material must reject after staged shard cost.")
	_check(_capture(f) == before, "Missing rune must preserve socket and shard balance.")
	for slot: int in [1, 2, 4]:
		var rarity: String = f.items[slot].snapshot().rarity
		var result: Dictionary = _craft(f, slot, "salvage")
		_check(result.error.is_empty() and result.yields["material.shard"] == f.crafting.policy().salvage_yields[rarity], "Every authored rarity salvage yield must be applied deterministically.")
	var invalid := Fixture.Word.new()
	invalid.content_id = "runeword.invalid"
	invalid.allowed_bases = ["item.wand"]
	invalid.runes = ["rune.spark", "rune.unknown"]
	invalid.effects = [Fixture.effect("item_effect.word", 2)]
	var rejected := Fixture.Crafting.new()
	_check(not rejected.load_definitions([preload("res://tests/fixtures/items/spark_rune.tres")], [invalid]).is_empty() and not invalid.is_frozen(), "Unknown recipe runes must fail before freezing definitions.")
	invalid.runes = ["rune.spark", "rune.spark"]
	_check(rejected.load_definitions([preload("res://tests/fixtures/items/spark_rune.tres")], [invalid]).is_empty(), "Repeated rune IDs are a valid ordered recipe.")
	_check(not rejected.bases_error({}).is_empty(), "Runeword base references must resolve during item publication.")
	var policy := preload("res://game/simulation/items/crafting_policy.gd").new()
	policy.reroll_rate = 0
	_check(not Fixture.Crafting.new().load_definitions([], [], policy).is_empty() and not policy.is_frozen(), "Invalid policy rates must reject publication.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
