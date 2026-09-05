class_name ItemGenerator
extends RefCounted

const World = preload("res://game/simulation/items/item_world.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Rules = preload("res://game/simulation/items/rarity_rules.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const SEARCH_BUDGET := 100000


static func generate(world: Variant, streams: Variant, definition_id: String, level: Variant, rarity: String) -> Dictionary:
	if not world is World or world.item_catalog() == null or not streams is Streams or not streams.is_initialized():
		return _failure("Generation requires an item world and initialized RNG streams.")
	var catalog: RefCounted = world.item_catalog()
	var definition: Resource = catalog.get_definition(definition_id)
	if definition == null or not definition.allowed_rarities.has(rarity) or not Instance._integer(level, 1) or level > 2147483647:
		return _failure("Unknown definition, unsupported rarity, or invalid item level.")
	var affixes: RefCounted = catalog.affix_catalog()
	var fixed: Array[Resource] = []
	for id: String in definition.fixed_affixes:
		var affix: Resource = affixes.get_definition(id)
		if affix.eligible_tiers(int(level), Rules.tier_ceiling(rarity)).is_empty():
			return _failure("Fixed affix has no eligible tier at the requested level.")
		fixed.append(affix)
	var candidates: Array[Resource] = []
	for id: String in affixes.ids():
		var affix: Resource = affixes.get_definition(id)
		if affix.supports(definition) and not affix.eligible_tiers(int(level), Rules.tier_ceiling(rarity)).is_empty() and _compatible(affix, fixed):
			candidates.append(affix)
	var staged := Streams.new()
	var restore_errors: PackedStringArray = staged.restore(streams.snapshot())
	assert(restore_errors.is_empty(), "An initialized RNG snapshot must restore.")
	var loot: RefCounted = staged.get_stream(Streams.LOOT)
	var bounds: Array = Rules.RANDOM_COUNTS[rarity]
	var selected: Array[Resource] = []
	if bounds[1] > 0:
		# Stable ordering followed by a loot-only shuffle makes publication order irrelevant.
		for index in range(candidates.size() - 1, 0, -1):
			var other: int = loot.next_int(0, index)
			var temporary: Resource = candidates[index]
			candidates[index] = candidates[other]
			candidates[other] = temporary
		var count: int = loot.next_int(bounds[0], bounds[1])
		var budget := [SEARCH_BUDGET]
		var found := false
		while count >= bounds[0] and not found:
			selected.clear()
			found = _select(candidates, 0, count, fixed, selected, budget)
			count -= 1
		if not found:
			return _failure("No compatible affix combination within rarity/search bounds.")
	var fields := {"item_level": int(level), "rarity": rarity, "affixes": [], "rolls": []}
	for affix: Resource in fixed + selected:
		var tiers: Array[Resource] = affix.eligible_tiers(int(level), Rules.tier_ceiling(rarity))
		var tier: Resource = tiers.back() if fixed.has(affix) else tiers[loot.next_int(0, tiers.size() - 1)]
		var value: float = tier.minimum
		if tier.minimum != tier.maximum:
			value = clampf(snappedf(lerpf(tier.minimum, tier.maximum, float(loot.next_int(0, 1000000)) / 1000000.0), 0.000001), tier.minimum, tier.maximum)
		fields.affixes.append(affix.content_id)
		fields.rolls.append({"affix_id": affix.content_id, "tier": tier.number, "value": value})
	var result: Dictionary = world.create_item(definition_id, fields)
	if result.error.is_empty():
		# Commit only after identity allocation and all item legality checks succeed.
		var errors: PackedStringArray = streams.restore(staged.snapshot())
		assert(errors.is_empty(), "Generated RNG state must remain valid.")
	return result


static func _select(candidates: Array[Resource], start: int, remaining: int, fixed: Array[Resource], selected: Array[Resource], budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] < 0:
		return false
	if remaining == 0:
		return true
	if candidates.size() - start < remaining:
		return false
	for index in range(start, candidates.size()):
		if budget[0] <= 0:
			return false
		var candidate: Resource = candidates[index]
		if not _compatible(candidate, fixed) or not _compatible(candidate, selected):
			continue
		selected.append(candidate)
		if _select(candidates, index + 1, remaining - 1, fixed, selected, budget):
			return true
		selected.pop_back()
	return false


static func _compatible(candidate: Resource, selected: Array[Resource]) -> bool:
	for prior: Resource in selected:
		if candidate.conflicts(prior):
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"item": null, "error": error}
