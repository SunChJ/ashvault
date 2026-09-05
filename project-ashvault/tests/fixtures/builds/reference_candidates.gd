extends RefCounted

const Fixture = preload("res://tests/fixtures/items/equipment_fixture.gd")
const Build = preload("res://game/infrastructure/headless/build_loadout.gd")


static func create(dominant_rarity: String = "") -> Dictionary:
	var affixes: Array = []
	for index in range(3):
		var affix: Resource = Fixture.affix("affix.reference.a%d" % index, ["slot.weapon", "slot.head"], 0)
		affix.group_id = "affix_group.reference.g%d" % index
		affix.stat_id = Build.STATS[0]
		affixes.append(affix)
	var affix_catalog := Fixture.Affixes.new()
	assert(affix_catalog.load_definitions(affixes).is_empty())
	var definitions: Array = []
	# Deliberate tradeoffs for harness regression, not release item balance.
	for row: Array in [["white", -1, 0], ["blue", 2, 8], ["gold", 0, 100], ["green", 3, 100], ["purple", 1, 0.7], ["red", 0, 10], ["set", 0, 8]]:
		var item: Resource = Fixture.item("item.reference." + row[0], "slot.weapon")
		var rarities: Array[String] = [row[0]]
		item.allowed_rarities = rarities
		var effects: Array[Resource] = []
		if row[1] >= 0:
			effects.append(Fixture.effect("item_effect.reference", row[2], Build.STATS[row[1]]))
		if row[0] == dominant_rarity:
			effects.clear()
			for index in range(Build.STATS.size()):
				effects.append(Fixture.effect("item_effect.dominant.s%d" % index, [10000, 0.7, 20, 10000][index], Build.STATS[index]))
		item.base_effects = effects
		if row[0] in ["green", "purple", "red", "set"]:
			var fixed: Array[String] = ["affix.reference.a0"]
			item.fixed_affixes = fixed
		match row[0]:
			"green": item.drop_source_id = "drop_source.reference"
			"purple": item.interaction_id = "interaction.reference"
			"red": item.rule_id = "rule.reference"
			"set": item.set_id = "set.reference"
		definitions.append(item)
	for rarity: String in ["white", "red"]:
		var head: Resource = Fixture.item("item.reference.head_" + rarity, "slot.head")
		var rarities: Array[String] = [rarity]
		head.allowed_rarities = rarities
		var effects: Array[Resource] = [Fixture.effect("item_effect.head", 1 if rarity == "white" else 2, Build.STATS[0])]
		head.base_effects = effects
		if rarity == "red":
			var fixed: Array[String] = ["affix.reference.a0"]
			head.fixed_affixes = fixed
			head.rule_id = "rule.reference.head"
		definitions.append(head)
	var catalog := Fixture.Catalog.new()
	assert(catalog.load_definitions(definitions, Fixture.Tags.new(), affix_catalog).is_empty())
	var world := Fixture.World.new()
	assert(world.configure("profile.reference", catalog).is_empty())
	var uids: Dictionary = {}
	for rarity: String in ["white", "blue", "gold", "green", "purple", "red", "set"]:
		var count := 3 if rarity == "green" else (2 if rarity == "purple" else (1 if rarity in ["red", "set"] else 0))
		var selected: Array = []
		var rolls: Array = []
		for index in range(count):
			var id := "affix.reference.a%d" % index
			selected.append(id)
			rolls.append({"affix_id": id, "tier": 1, "value": 0})
		var created: Dictionary = world.create_item("item.reference." + rarity, {"rarity": rarity, "affixes": selected, "rolls": rolls})
		assert(created.error.is_empty(), created.error)
		uids[rarity] = created.item.uid()
	for rarity: String in ["white", "red"]:
		var fields := {"rarity": rarity}
		if rarity == "red":
			fields["affixes"] = ["affix.reference.a0"]
			fields["rolls"] = [{"affix_id": "affix.reference.a0", "tier": 1, "value": 0}]
		var created: Dictionary = world.create_item("item.reference.head_" + rarity, fields)
		assert(created.error.is_empty(), created.error)
		uids["head_" + rarity] = created.item.uid()
	var bonuses: Array = []
	for count in [2, 3, 4]:
		var bonus := Fixture.Bonus.new()
		bonus.set_id = "set.reference"
		bonus.pieces = count
		bonus.effects = [Fixture.effect("item_effect.reference.bonus", count, Build.STATS[0])]
		bonuses.append(bonus)
	return {"world": world, "uids": uids, "bonuses": bonuses}
