extends RefCounted

const Affix = preload("res://game/simulation/items/affix_definition.gd")
const Tier = preload("res://game/simulation/items/affix_tier.gd")
const Affixes = preload("res://game/simulation/items/affix_catalog.gd")
const Item = preload("res://game/simulation/items/item_definition.gd")
const Catalog = preload("res://game/simulation/items/item_catalog.gd")
const Tags = preload("res://game/content/tag_registry.gd")


static func make_affix(id: String, group: String, slots: Array[String] = ["slot.weapon"]) -> Resource:
	var affix := Affix.new()
	affix.content_id = id
	affix.group_id = group
	affix.stat_id = "stat.power"
	affix.allowed_slots = slots
	var tiers: Array[Resource] = []
	for number in range(1, 6):
		var tier := Tier.new()
		tier.number = number
		tier.minimum_level = 1 if number == 1 else (number - 1) * 10
		tier.minimum = number * 2
		tier.maximum = number * 2 + 1
		tiers.append(tier)
	affix.tiers = tiers
	return affix


static func make_item(id: String, rarities: Array[String] = ["white", "blue", "gold"]) -> Resource:
	var item := Item.new()
	item.content_id = id
	item.display_name = "Fixture Item"
	item.equipment_slot = "slot.weapon"
	item.allowed_rarities = rarities
	return item


static func item_id(rarity: String, sample: int = 0) -> String:
	return ["item.base", "item.other", "item.body"][sample % 3] if rarity in ["white", "blue", "gold"] else "item." + rarity


static func catalog(reverse: bool = false) -> RefCounted:
	var definitions: Array = []
	for name: String in ["power", "speed", "life", "mana", "guard", "implicit"]:
		definitions.append(make_affix("affix." + name, "affix_group." + name))
	definitions.append(make_affix("affix.power_alt", "affix_group.power"))
	definitions.append(make_affix("affix.armor", "affix_group.armor", ["slot.body"]))
	var exclusive: Resource = make_affix("affix.exclusive", "affix_group.exclusive")
	exclusive.allowed_bases = _strings(["item.other"])
	definitions.append(exclusive)
	definitions[0].excluded_affixes = _strings(["affix.speed"])
	var body: Resource = make_item("item.body")
	body.equipment_slot = "slot.body"
	var items: Array = [make_item("item.base"), make_item("item.other"), body]
	for rarity: String in ["green", "purple", "red", "set"]:
		var item: Resource = make_item("item." + rarity, [rarity])
		item.fixed_affixes = _strings(["affix.implicit"])
		match rarity:
			"green": item.drop_source_id = "drop_source.fixture"
			"purple": item.interaction_id = "interaction.fixture"
			"red": item.rule_id = "rule.fixture"
			"set": item.set_id = "set.fixture"
		items.append(item)
	var blocked: Resource = make_item("item.blocked", ["green"])
	blocked.fixed_affixes = _strings(["affix.implicit"])
	blocked.drop_source_id = "drop_source.blocked"
	blocked.equipment_slot = "slot.empty"
	# Supply the fixed affix but no random affix that supports this slot.
	var isolated := make_affix("affix.isolated", "affix_group.isolated", ["slot.empty"])
	definitions.append(isolated)
	var trap: Resource = make_item("item.trap", ["green"])
	trap.equipment_slot = "slot.trap"
	trap.drop_source_id = "drop_source.trap"
	trap.fixed_affixes = _strings(["affix.trap_implicit"])
	items.append(trap)
	for name: String in ["a", "b", "bad", "implicit"]:
		var candidate: Resource = make_affix("affix.trap_" + name, "affix_group.trap_" + name, ["slot.trap"])
		if name == "bad":
			candidate.excluded_affixes = _strings(["affix.trap_a", "affix.trap_b"])
		definitions.append(candidate)
	if reverse:
		definitions.reverse()
	var final_affixes := Affixes.new()
	assert(final_affixes.load_definitions(definitions).is_empty())
	blocked.fixed_affixes = _strings(["affix.isolated"])
	items.append(blocked)
	if reverse:
		items.reverse()
	var result := Catalog.new()
	assert(result.load_definitions(items, Tags.new(), final_affixes).is_empty())
	return result


static func illegal_record(original: Dictionary, mutation: String) -> Dictionary:
	var record: Dictionary = original.duplicate(true)
	record.affixes = ["affix.power"]
	record.rolls = [{"affix_id": "affix.power", "tier": 1, "value": 2.5}]
	match mutation:
		"unknown":
			record.affixes = ["affix.missing"]
			record.rolls[0].affix_id = "affix.missing"
		"missing_roll": record.rolls.clear()
		"duplicate_group", "excluded":
			var id := "affix.power_alt" if mutation == "duplicate_group" else "affix.speed"
			record.affixes.append(id)
			record.rolls.append({"affix_id": id, "tier": 1, "value": 2.5})
		"slot", "base":
			var id := "affix.armor" if mutation == "slot" else "affix.exclusive"
			record.affixes = [id]
			record.rolls[0].affix_id = id
		"level":
			record.item_level = 1
			record.rolls[0].tier = 2
			record.rolls[0].value = 4.5
		"tier":
			record.rarity = "gold"
			record.rolls[0].tier = 5
			record.rolls[0].value = 10.5
		"count":
			record.affixes = ["affix.life", "affix.mana", "affix.guard"]
			record.rolls = []
			for id: String in record.affixes:
				record.rolls.append({"affix_id": id, "tier": 1, "value": 2.5})
		"bounds": record.rolls[0].value = 100
		"rarity": record.rarity = "white"
	return record


static func test_publication(failures: Array[String]) -> void:
	var affix: Resource = make_affix("affix.frozen", "affix_group.frozen")
	var catalog_value := Affixes.new()
	if not catalog_value.load_definitions([affix]).is_empty():
		failures.append("Valid affix publication must succeed.")
	affix.group_id = "affix_group.changed"
	affix.tiers[0].maximum = 100
	var exposed: Array[Resource] = affix.tiers
	exposed.clear()
	if affix.group_id != "affix_group.frozen" or affix.tiers.size() != 5 or affix.tiers[0].maximum != 3:
		failures.append("Affix publication must freeze nested tiers and copy collections.")
	var invalid: Resource = make_affix("affix.bad", "affix_group.bad")
	invalid.excluded_affixes = _strings(["affix.missing"])
	var rejected := Affixes.new()
	if rejected.load_definitions([invalid]).is_empty() or invalid.is_frozen() or invalid.tiers[0].is_frozen():
		failures.append("Invalid affix publication must not freeze any Resource.")
	for mutation: String in ["bounds", "nan", "level", "tier", "slots", "group"]:
		var bad: Resource = make_affix("affix.bad", "affix_group.bad")
		match mutation:
			"bounds": bad.tiers[0].maximum = -1
			"nan": bad.tiers[0].minimum = NAN
			"level": bad.tiers[1].minimum_level = 0
			"tier": bad.tiers[1].number = 1
			"slots": bad.allowed_slots = _strings([])
			"group": bad.group_id = "invalid"
		var target := Affixes.new()
		if target.load_definitions([bad]).is_empty() or bad.is_frozen():
			failures.append("Invalid affix fields must reject publication: %s" % mutation)
	var supported := Affixes.new()
	var implicit: Resource = make_affix("affix.implicit", "affix_group.implicit")
	assert(supported.load_definitions([implicit]).is_empty())
	for rarity: String in ["green", "purple", "red", "set"]:
		var special: Resource = make_item("item.special", [rarity])
		special.fixed_affixes = _strings(["affix.implicit"])
		var target := Catalog.new()
		if target.load_definitions([special], Tags.new(), supported).is_empty() or special.is_frozen():
			failures.append("Special definitions must require their source/interaction/rule/set identity.")
	var constrained: Resource = make_affix("affix.constrained", "affix_group.constrained")
	constrained.allowed_bases = _strings(["item.missing"])
	var constrained_catalog := Affixes.new()
	assert(constrained_catalog.load_definitions([constrained]).is_empty())
	var ordinary: Resource = make_item("item.base")
	if Catalog.new().load_definitions([ordinary], Tags.new(), constrained_catalog).is_empty() or ordinary.is_frozen():
		failures.append("Item publication must validate affix base references before freezing.")


static func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	result.assign(values)
	return result
