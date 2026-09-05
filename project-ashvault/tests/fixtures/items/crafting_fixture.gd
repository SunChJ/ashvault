extends RefCounted

const Crafting = preload("res://game/simulation/items/crafting_catalog.gd")
const Rune = preload("res://game/simulation/items/rune_definition.gd")
const Word = preload("res://game/simulation/items/runeword_definition.gd")
const Effect = preload("res://game/simulation/items/item_stat_effect.gd")
const Definition = preload("res://game/simulation/items/item_definition.gd")
const Catalog = preload("res://game/simulation/items/item_catalog.gd")
const Affixes = preload("res://game/simulation/items/affix_catalog.gd")
const Tags = preload("res://game/content/tag_registry.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Ownership = preload("res://game/simulation/items/inventory_state.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")


static func effect(id: String, amount: float) -> Resource:
	var result := Effect.new()
	result.effect_id = id
	result.stat_id = "stat.power"
	result.amount = amount
	return result


static func base(id: String) -> Resource:
	var result := Definition.new()
	result.content_id = id
	result.display_name = "Crafting Wand"
	result.equipment_slot = "slot.weapon"
	result.max_sockets = 2
	result.base_effects = [effect("item_effect.base", 10)]
	return result


static func create() -> Dictionary:
	var spark: Resource = preload("res://tests/fixtures/items/spark_rune.tres")
	var tide := Rune.new()
	tide.content_id = "rune.tide"
	tide.effects = [effect("item_effect.tide", 3)]
	var word := Word.new()
	word.content_id = "runeword.storm"
	word.runes = ["rune.spark", "rune.tide"]
	word.allowed_bases = ["item.wand"]
	word.effects = [effect("item_effect.storm", 5)]
	var crafting := Crafting.new()
	var error: String = crafting.load_definitions([tide, spark], [word])
	assert(error.is_empty(), error)
	var affixes := Affixes.new()
	assert(affixes.load_definitions([preload("res://tests/fixtures/items/power_affix.tres").duplicate(true)]).is_empty())
	var unique: Resource = base("item.unique")
	var red: Array[String] = ["red"]
	var fixed: Array[String] = ["affix.power"]
	unique.allowed_rarities = red
	unique.fixed_affixes = fixed
	unique.rule_id = "rule.fixture"
	var catalog := Catalog.new()
	assert(catalog.load_definitions([base("item.wand"), base("item.other"), unique], Tags.new(), affixes, crafting).is_empty())
	var world := World.new()
	world.configure("profile.craft", catalog)
	var inventory := Ownership.new()
	inventory.configure(world, "authority.local")
	inventory.register_owner("authority.local", "actor.player", 5, 1)
	var items: Array = []
	for rarity: String in ["white", "blue", "gold", "white", "red"]:
		var fields: Dictionary = {"rarity": rarity}
		if rarity != "white":
			fields.affixes = ["affix.power"]
			fields.rolls = [{"affix_id": "affix.power", "tier": 2, "value": 3.5}]
		var definition_id: String = "item.unique" if rarity == "red" else ("item.other" if items.size() == 3 else "item.wand")
		var item: RefCounted = world.create_item(definition_id, fields).item
		inventory.place_item("authority.local", "actor.player", "bag", items.size(), item.uid())
		items.append(item)
	var streams := Streams.new()
	streams.initialize(929)
	var stat := Stat.new()
	stat.configure("stat.power", 100)
	var registry := Registry.new()
	registry.load_definitions([stat])
	inventory.configure_equipment("authority.local", "actor.player", registry)
	return {"world": world, "inventory": inventory, "streams": streams, "crafting": crafting, "word": word, "tide": tide, "items": items}
