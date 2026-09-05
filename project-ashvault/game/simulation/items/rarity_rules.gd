class_name ItemRarityRules
extends RefCounted

const Instance = preload("res://game/simulation/items/item_instance.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
const RARITIES := Instance.RARITIES
const RANDOM_COUNTS := {"white": [0, 0], "blue": [1, 2], "gold": [1, 4], "green": [2, 3], "purple": [1, 2], "red": [0, 0], "set": [0, 0]}


static func tier_ceiling(rarity: String) -> int:
	return 5 if rarity == "blue" else (0 if rarity == "white" else 4)


static func targeted_reroll_weight(rarity: String) -> int:
	return 1 if rarity == "blue" else (2 if rarity in ["gold", "green", "purple", "red", "set"] else -1)


static func definition_error(definition: Resource, affixes: RefCounted) -> String:
	if definition.allowed_rarities.is_empty():
		return "Item must allow at least one rarity."
	var seen: Dictionary = {}
	for rarity: String in definition.allowed_rarities:
		if not RARITIES.has(rarity) or seen.has(rarity):
			return "Item allowed rarities must be known and unique."
		seen[rarity] = true
		if rarity in ["green", "purple", "red", "set"] and definition.allowed_rarities.size() != 1:
			return "Special item definitions must declare one rarity."
	var rarity: String = definition.allowed_rarities[0]
	var count: int = definition.fixed_affixes.size()
	if rarity in ["white", "blue", "gold"] and count != 0:
		return "Ordinary bases cannot declare fixed affixes."
	if rarity == "green" and count != 1:
		return "Green items require one fixed implicit affix."
	if rarity == "purple" and (count < 1 or count > 2):
		return "Purple items require one or two fixed affixes."
	if rarity in ["red", "set"] and (count < 1 or count > 4):
		return "Red and set items require one to four fixed affixes."
	for entry: Array in [["green", definition.drop_source_id, "drop_source."], ["purple", definition.interaction_id, "interaction."], ["red", definition.rule_id, "rule."], ["set", definition.set_id, "set."]]:
		if rarity == entry[0]:
			if not entry[1].begins_with(entry[2]) or not StableIdContract.is_valid(entry[1]):
				return "Special item requires its stable source/interaction/rule/set ID."
		elif not entry[1].is_empty():
			return "Special item identity does not match its rarity."
	var selected: Array[Resource] = []
	for id: String in definition.fixed_affixes:
		var affix: Resource = affixes.get_definition(id)
		if affix == null or not affix.supports(definition) or affix.eligible_tiers(2147483647, tier_ceiling(rarity)).is_empty():
			return "Fixed affix is unknown or incompatible with its base/slot."
		for prior: Resource in selected:
			if affix.conflicts(prior):
				return "Fixed affixes have duplicate groups or exclusions."
		selected.append(affix)
	return ""


static func record_error(record: Dictionary, definition: Resource, affixes: RefCounted) -> String:
	var structural := Instance.validation_error(record, definition)
	if not structural.is_empty():
		return structural
	if not definition.allowed_rarities.has(record.rarity) or record.item_level > 2147483647:
		return "Item rarity or level is not allowed by its definition."
	for id: String in definition.fixed_affixes:
		if not record.affixes.has(id):
			return "Item is missing a mandatory fixed affix."
	var random_count: int = record.affixes.size() - definition.fixed_affixes.size()
	var bounds: Array = RANDOM_COUNTS[record.rarity]
	# Empty ordinary items remain valid; generation always chooses at least one.
	var minimum: int = 0 if record.rarity in ["blue", "gold"] else bounds[0]
	if random_count < minimum or random_count > bounds[1] or record.affixes.size() > 4:
		return "Item affix count violates its rarity budget."
	if record.rolls.size() != record.affixes.size():
		return "Every attached affix requires exactly one roll."
	var selected: Array[Resource] = []
	for id: String in record.affixes:
		var affix: Resource = affixes.get_definition(id)
		if affix == null or not affix.supports(definition):
			return "Item affix is unknown or violates base/slot restrictions."
		for prior: Resource in selected:
			if affix.conflicts(prior):
				return "Item affixes violate group or exclusion constraints."
		selected.append(affix)
	for roll: Dictionary in record.rolls:
		var affix: Resource = affixes.get_definition(roll.affix_id)
		var valid := false
		for tier: Resource in affix.eligible_tiers(int(record.item_level), tier_ceiling(record.rarity)):
			if tier.number == roll.tier and roll.value >= tier.minimum and roll.value <= tier.maximum:
				valid = true
		if not valid:
			return "Affix roll violates its level, rarity tier ceiling, or numeric bounds."
	return ""
