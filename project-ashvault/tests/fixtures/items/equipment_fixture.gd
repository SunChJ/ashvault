extends RefCounted

const Item = preload("res://game/simulation/items/item_definition.gd")
const Catalog = preload("res://game/simulation/items/item_catalog.gd")
const World = preload("res://game/simulation/items/item_world.gd")
const Affix = preload("res://game/simulation/items/affix_definition.gd")
const Tier = preload("res://game/simulation/items/affix_tier.gd")
const Affixes = preload("res://game/simulation/items/affix_catalog.gd")
const Effect = preload("res://game/simulation/items/item_stat_effect.gd")
const Bonus = preload("res://game/simulation/items/equipment_set_bonus.gd")
const Equipment = preload("res://game/simulation/items/equipment_state.gd")
const Modifier = preload("res://game/simulation/stats/stat_modifier.gd")
const Stat = preload("res://game/simulation/stats/stat_definition.gd")
const Registry = preload("res://game/simulation/stats/stat_registry.gd")
const Tags = preload("res://game/content/tag_registry.gd")


static func effect(id: String, amount: float, stat_id: String = "stat.power") -> Resource:
	var value := Effect.new()
	value.effect_id = id
	value.stat_id = stat_id
	value.amount = amount
	return value


static func affix(id: String, slots: Array[String], value: float) -> Resource:
	var result := Affix.new()
	result.content_id = id
	result.group_id = "affix_group.fixture"
	result.stat_id = "stat.power"
	result.allowed_slots = slots
	var tier := Tier.new()
	tier.minimum = value
	tier.maximum = value
	result.tiers = [tier]
	return result


static func item(id: String, slot: String) -> Resource:
	var result := Item.new()
	result.content_id = id
	result.display_name = "Equipment Fixture"
	result.equipment_slot = slot
	result.base_effects = [effect("item_effect.base", 1)]
	return result


static func create() -> Dictionary:
	var definitions: Array = []
	var power: Resource = affix("affix.power", ["slot.weapon"], 2)
	var implicit: Resource = affix("affix.set", ["slot.head", "slot.body", "slot.hands", "slot.feet"], 1)
	var affixes := Affixes.new()
	assert(affixes.load_definitions([power, implicit]).is_empty())
	for slot: String in Equipment.SLOTS:
		var definition: Resource = item("item." + slot.get_slice(".", 1), slot)
		if slot in ["slot.head", "slot.body", "slot.hands", "slot.feet"]:
			var rarities: Array[String] = ["set"]
			var fixed: Array[String] = ["affix.set"]
			definition.allowed_rarities = rarities
			definition.fixed_affixes = fixed
			definition.set_id = "set.fixture"
		definitions.append(definition)
	var two_handed: Resource = item("item.two_handed", "slot.weapon")
	two_handed.two_handed = true
	var conditional: Resource = effect("item_effect.empowered", 1)
	conditional.operation = Modifier.Operation.MORE
	conditional.condition_id = "condition.empowered"
	var weapon_effects: Array[Resource] = [effect("item_effect.base", 10), conditional]
	two_handed.base_effects = weapon_effects
	definitions.append(two_handed)
	var invalid: Resource = item("item.invalid_stat", "slot.weapon")
	var unknown_effects: Array[Resource] = [effect("item_effect.unknown", 1, "stat.unknown")]
	invalid.base_effects = unknown_effects
	definitions.append(invalid)
	var special: Resource = item("item.special", "slot.weapon")
	var special_rarities: Array[String] = ["red"]
	var special_affixes: Array[String] = ["affix.power"]
	special.allowed_rarities = special_rarities
	special.fixed_affixes = special_affixes
	special.rule_id = "rule.fixture"
	definitions.append(special)
	var catalog := Catalog.new()
	assert(catalog.load_definitions(definitions, Tags.new(), affixes).is_empty())
	var world := World.new()
	assert(world.configure("profile.gear", catalog).is_empty())
	var items: Dictionary = {}
	for slot: String in Equipment.SLOTS:
		var fields: Dictionary = {}
		if slot == "slot.weapon":
			fields = {"rarity": "blue", "affixes": ["affix.power"], "rolls": [{"affix_id": "affix.power", "tier": 1, "value": 2}]}
		elif slot in ["slot.head", "slot.body", "slot.hands", "slot.feet"]:
			fields = {"rarity": "set", "affixes": ["affix.set"], "rolls": [{"affix_id": "affix.set", "tier": 1, "value": 1}]}
		var created: Dictionary = world.create_item("item." + slot.get_slice(".", 1), fields)
		assert(created.error.is_empty())
		items[slot] = created.item
	var stat := Stat.new()
	stat.configure("stat.power", 100)
	var registry := Registry.new()
	assert(registry.load_definitions([stat]).is_empty())
	var bonuses: Array[Resource] = []
	for count in [2, 3, 4]:
		var bonus := Bonus.new()
		bonus.set_id = "set.fixture"
		bonus.pieces = count
		bonus.effects = [effect("item_effect.threshold", count)]
		bonuses.append(bonus)
	return {"world": world, "registry": registry, "items": items, "set_bonuses": bonuses,
		"two_handed": world.create_item("item.two_handed").item,
		"invalid_stat": world.create_item("item.invalid_stat").item,
		"special": world.create_item("item.special", {"rarity": "red", "affixes": ["affix.power"], "rolls": [{"affix_id": "affix.power", "tier": 1, "value": 2}]}).item}


static func test_validation(failures: Array[String]) -> void:
	var invalid: Resource = item("item.bad_hands", "slot.head")
	invalid.two_handed = true
	if Catalog.new().load_definitions([invalid], Tags.new()).is_empty() or invalid.is_frozen():
		failures.append("Two-handed non-weapons must fail publication atomically.")
	var duplicate: Resource = item("item.duplicate", "slot.weapon")
	var repeated: Array[Resource] = [effect("item_effect.same", 1), effect("item_effect.same", 2)]
	duplicate.base_effects = repeated
	if Catalog.new().load_definitions([duplicate], Tags.new()).is_empty() or repeated[0].is_frozen():
		failures.append("Duplicate base effect IDs must fail before freezing.")
	var conversion: Resource = affix("affix.bad_conversion", ["slot.weapon"], 2)
	conversion.operation = Modifier.Operation.CONVERSION
	conversion.target_stat_id = "stat.other"
	if Affixes.new().load_definitions([conversion]).is_empty():
		failures.append("Affix operation constraints must validate full roll bounds.")


static func test_operations(failures: Array[String]) -> void:
	var weapon: Resource = item("item.converting", "slot.weapon")
	var effects: Array[Resource] = [effect("item_effect.base", 10)]
	weapon.base_effects = effects
	var conversion: Resource = affix("affix.conversion", ["slot.weapon"], 0.5)
	conversion.operation = Modifier.Operation.CONVERSION
	conversion.target_stat_id = "stat.lightning"
	var increased: Resource = affix("affix.increased", ["slot.weapon"], 1)
	increased.group_id = "affix_group.increased"
	increased.operation = Modifier.Operation.INCREASED
	var affixes := Affixes.new()
	assert(affixes.load_definitions([conversion, increased]).is_empty())
	var catalog := Catalog.new()
	assert(catalog.load_definitions([weapon], Tags.new(), affixes).is_empty())
	var world := World.new()
	world.configure("profile.operations", catalog)
	var instance: RefCounted = world.create_item("item.converting", {"rarity": "blue", "affixes": ["affix.conversion", "affix.increased"], "rolls": [{"affix_id": "affix.conversion", "tier": 1, "value": 0.5}, {"affix_id": "affix.increased", "tier": 1, "value": 1}]}).item
	var stat := Stat.new()
	stat.configure("stat.power", 100)
	var lightning := Stat.new()
	lightning.configure("stat.lightning", 0)
	var registry := Registry.new()
	assert(registry.load_definitions([stat, lightning]).is_empty())
	var gear := Equipment.new()
	assert(gear.configure(world, registry).is_empty())
	var equipped: Dictionary = gear.transact({"slot.weapon": instance.uid()}, 1)
	if not equipped.error.is_empty() or gear.stats().value("stat.power") != 110 or gear.stats().value("stat.lightning") != 110:
		failures.append("Equipment must delegate increased and conversion ordering to StatResolver.")
	if gear.stats().explanation("stat.lightning").incoming_conversions.is_empty():
		failures.append("Converted item contributions must preserve resolver explanations.")
	var source := "equipment.profile.operations.i1.affix.increased"
	var exposed: Dictionary = gear.sources()
	exposed[source].uid = "changed"
	if gear.sources()[source].uid != instance.uid():
		failures.append("Contribution source metadata must not alias live equipment.")
	weapon.base_effects[0].amount = 999
	conversion.operation = Modifier.Operation.FLAT
	if weapon.base_effects[0].amount != 10 or conversion.operation != Modifier.Operation.CONVERSION:
		failures.append("Base effects and affix mapping must remain frozen after publication.")
