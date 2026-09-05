class_name CraftingRecipe
extends RefCounted

const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Rules = preload("res://game/simulation/items/rarity_rules.gd")
const Crafting = preload("res://game/simulation/items/crafting_catalog.gd")


static func plan(record: Dictionary, catalog: RefCounted, streams: Variant, recipe: String, target: String = "") -> Dictionary:
	if not streams is Streams or not streams.is_initialized():
		return _failure("Crafting requires initialized RNG streams.")
	var crafting: RefCounted = catalog.crafting_catalog()
	var policy: Resource = crafting.policy()
	var definition: Resource = catalog.get_definition(record.definition_id)
	var staged: Dictionary = record.duplicate(true)
	var costs: Dictionary = {}
	var yields: Dictionary = {}
	var rng := Streams.new()
	var errors: PackedStringArray = rng.restore(streams.snapshot())
	assert(errors.is_empty(), "Live RNG must restore for recipe planning.")
	match recipe:
		"salvage":
			if not target.is_empty():
				return _failure("Salvage has no target parameter.")
			yields["material.shard"] = int(policy.salvage_yields[record.rarity])
		"quality":
			if not target.is_empty() or record.quality >= Crafting.MAX_QUALITY:
				return _failure("Quality is capped at 20 and has no target parameter.")
			staged.quality += 1
			costs["material.shard"] = int(staged.quality) * policy.quality_rate
		"socket":
			if not target.is_empty() or record.rarity != "white" or record.sockets.size() >= definition.max_sockets or crafting.active_word(record) != null:
				return _failure("Only an unfinished white base below socket capacity can gain a socket.")
			staged.sockets.append("")
			costs["material.shard"] = staged.sockets.size() * policy.socket_rate
		"insert_rune":
			if crafting.rune(target) == null or not record.sockets.has(""):
				return _failure("Rune insertion requires a published rune and an empty socket.")
			staged.sockets[staged.sockets.find("")] = target
			costs["material.shard"] = policy.insertion_cost
			costs[target] = 1
		"reroll":
			if not record.affixes.has(target) or definition.fixed_affixes.has(target) or Rules.targeted_reroll_weight(record.rarity) < 1:
				return _failure("Targeted reroll requires an attached, non-fixed affix.")
			var index := -1
			for position in staged.rolls.size():
				if staged.rolls[position].affix_id == target:
					index = position
			var affix: Resource = catalog.affix_catalog().get_definition(target)
			var tier: Resource
			for candidate: Resource in affix.eligible_tiers(int(record.item_level), Rules.tier_ceiling(record.rarity)):
				if candidate.number == staged.rolls[index].tier:
					tier = candidate
			if tier.minimum == tier.maximum:
				return _failure("A constant affix roll cannot be rerolled.")
			var draw: int = rng.get_stream(Streams.LOOT).next_int(0, 1000000)
			staged.rolls[index].value = clampf(snappedf(lerpf(tier.minimum, tier.maximum, float(draw) / 1000000.0), 0.000001), tier.minimum, tier.maximum)
			costs["material.shard"] = policy.reroll_rate * Rules.targeted_reroll_weight(record.rarity)
		_:
			return _failure("Unknown crafting recipe.")
	var error: String = catalog.validate_record(staged)
	if not error.is_empty():
		return _failure(error)
	return {"error": "", "record": staged, "costs": costs, "yields": yields, "rng": rng.snapshot(), "consumed": recipe == "salvage"}


static func _failure(error: String) -> Dictionary:
	return {"error": error}
