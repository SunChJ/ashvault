class_name BuildLoadout
extends RefCounted

const World = preload("res://game/simulation/items/item_world.gd")
const Equipment = preload("res://game/simulation/items/equipment_state.gd")
const Instance = preload("res://game/simulation/items/item_instance.gd")
const Stable = preload("res://game/content/stable_id.gd")
const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const FIELDS := ["schema_version", "build_id", "skills", "rotation", "duration_ticks", "root_seed", "loadout", "conditions", "objective", "base_stats"]
const STATS := [Catalog.POWER, Catalog.CRIT, Catalog.CRIT_MULTIPLIER, "stat.defense.armor"]
const OBJECTIVES := ["damage", "defense", "procs"]


static func validate(value: Variant, world: Variant) -> String:
	if not world is World or world.item_catalog() == null:
		return "Build requires a published candidate ItemWorld."
	if not fields(value, FIELDS) or not integer(value.schema_version, 1, 1):
		return "Build schema fields or version are invalid."
	if not value.build_id is String or not Stable.is_valid(value.build_id):
		return "Build requires a stable ID."
	if not integer(value.duration_ticks, 1, 3600) or not integer(value.root_seed, -2147483648, 2147483647):
		return "Build duration or seed is out of range."
	if not value.objective is String or not OBJECTIVES.has(value.objective):
		return "Unknown Build objective."
	if not fields(value.base_stats, STATS):
		return "Build requires explicit base combat stats."
	for id: String in STATS:
		var amount: Variant = value.base_stats[id]
		if not (amount is int or amount is float) or not is_finite(amount) or amount < 0 or amount > 1000000:
			return "Build stats must be finite and bounded."
	if value.base_stats[Catalog.CRIT] > 0.95 or value.base_stats[Catalog.CRIT_MULTIPLIER] < 1:
		return "Build critical stats are out of range."
	if not string_list(value.conditions) or value.conditions.size() > 32:
		return "Build conditions require distinct stable IDs."
	for id: String in value.conditions:
		if not Stable.is_valid(id):
			return "Build conditions require stable IDs."
	if not value.skills is Dictionary or value.skills.is_empty() or value.skills.size() > 6:
		return "Build requires skill ranks."
	for skill: Variant in value.skills:
		if not skill is String or skill_slot(skill) < 0 or not integer(value.skills[skill], 1, 20):
			return "Build skill or rank is invalid."
	if not value.rotation is Array or value.rotation.is_empty() or value.rotation.size() > 256:
		return "Build rotation must contain 1 to 256 casts."
	var previous := 0
	for cast: Variant in value.rotation:
		if not fields(cast, ["tick", "skill"]) or not integer(cast.tick, previous + 1, int(value.duration_ticks)) or not cast.skill is String or not value.skills.has(cast.skill):
			return "Build rotation requires ordered ticks and ranked skills."
		previous = int(cast.tick)
	if not value.loadout is Dictionary or value.loadout.is_empty() or value.loadout.size() > 8:
		return "Build requires 1 to 8 equipment selectors."
	for slot: Variant in value.loadout:
		if not slot is String or not Equipment.SLOTS.has(slot):
			return "Build equipment slot is unknown."
		var selector: Variant = value.loadout[slot]
		if fields(selector, ["uid"]):
			if not selector.uid is String or world.get_item(selector.uid) == null:
				return "Build exact item UID is unknown."
		elif fields(selector, ["bases", "affixes", "rarities"]):
			for name: String in ["bases", "affixes", "rarities"]:
				if not string_list(selector[name]):
					return "Build constraints require unique string arrays."
			for id: String in selector.bases:
				if world.item_catalog().get_definition(id) == null:
					return "Build constraint references an unknown base."
			for id: String in selector.affixes:
				if world.item_catalog().affix_catalog().get_definition(id) == null:
					return "Build constraint references an unknown affix."
			for rarity: String in selector.rarities:
				if not Instance.RARITIES.has(rarity):
					return "Build constraint rarity is unknown."
		else:
			return "Build selector must be an exact UID or base/affix/rarity constraints."
	return ""


static func resolve(value: Variant, world: Variant) -> Dictionary:
	var error := validate(value, world)
	if not error.is_empty():
		return {"error": error}
	var slots: Dictionary = {}
	var records: Array = world.snapshot().items
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.uid < b.uid)
	for slot: String in Equipment.SLOTS:
		if not value.loadout.has(slot):
			continue
		var selector: Dictionary = value.loadout[slot]
		if selector.has("uid"):
			slots[slot] = selector.uid
			continue
		for record: Dictionary in records:
			if world.item_catalog().get_definition(record.definition_id).equipment_slot != slot:
				continue
			if not selector.bases.is_empty() and not record.definition_id in selector.bases:
				continue
			if not selector.rarities.is_empty() and not record.rarity in selector.rarities:
				continue
			if not selector.affixes.all(func(id: String) -> bool: return record.affixes.has(id)):
				continue
			slots[slot] = record.uid
			break
		if not slots.has(slot):
			return {"error": "No candidate satisfies Build slot '%s'." % slot}
	return {"error": "", "slots": slots}


static func fields(value: Variant, names: Array) -> bool:
	return value is Dictionary and value.size() == names.size() and value.has_all(names)


static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= minimum and value <= maximum


static func string_list(value: Variant) -> bool:
	if not value is Array or value.size() > 128:
		return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is String or seen.has(entry):
			return false
		seen[entry] = true
	return true


static func skill_slot(id: String) -> int:
	for slot in Catalog.SKILLS.size():
		if Catalog.SKILLS[slot].id == id:
			return slot
	return -1
