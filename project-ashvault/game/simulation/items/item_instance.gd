class_name ItemInstance
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")
const MAX_SAFE_INTEGER := 9007199254740991
const RARITIES := ["white", "blue", "gold", "green", "purple", "red", "set"]
const FIELDS := ["uid", "definition_id", "item_level", "rarity", "affixes", "rolls", "sockets", "quality", "metadata"]
const DEFAULTS := {"item_level": 1, "rarity": "white", "affixes": [], "rolls": [], "sockets": [], "quality": 0, "metadata": {}}

var _data: Dictionary = {}

# ItemWorld publishes instances only after validating the complete record.

func _initialize(value: Dictionary) -> void:
	assert(_data.is_empty(), "Item instances cannot be reinitialized.")
	_data = value.duplicate(true)
	_data.item_level = int(_data.item_level)
	_data.quality = int(_data.quality)
	for roll: Dictionary in _data.rolls:
		roll.tier = int(roll.tier)
		roll.value = float(roll.value)


func uid() -> String:
	return _data.uid


func definition_id() -> String:
	return _data.definition_id


func snapshot() -> Dictionary:
	return _data.duplicate(true)


static func validation_error(value: Dictionary, definition: Resource) -> String:
	if value.size() != FIELDS.size():
		return "Item record has unexpected or missing fields."
	for field: String in FIELDS:
		if not value.has(field):
			return "Item record is missing '%s'." % field
	if not value.uid is String or not value.definition_id is String or value.definition_id != definition.content_id:
		return "Item identity does not match its definition."
	if not _integer(value.item_level, 1) or not _integer(value.quality, 0):
		return "Item level and quality must be JSON-safe non-negative integers; level starts at one."
	if not value.rarity is String or not RARITIES.has(value.rarity):
		return "Item rarity is unknown."
	if not value.affixes is Array or not value.rolls is Array or not value.sockets is Array or not value.metadata is Dictionary:
		return "Item affixes, rolls, sockets, and metadata have invalid container types."
	if value.affixes.size() > 32 or value.rolls.size() > 32 or value.sockets.size() > definition.max_sockets:
		return "Item content exceeds its bounded capacity."
	var seen: Dictionary = {}
	for affix: Variant in value.affixes:
		if not affix is String or not affix.begins_with("affix.") or not StableIdContract.is_valid(affix) or seen.has(affix):
			return "Item affixes must be unique stable affix IDs."
		seen[affix] = true
	var rolled: Dictionary = {}
	for roll: Variant in value.rolls:
		if not roll is Dictionary or roll.size() != 3 or not roll.has_all(["affix_id", "tier", "value"]):
			return "Item roll requires affix_id, tier, and value."
		if not roll.affix_id is String or not seen.has(roll.affix_id) or rolled.has(roll.affix_id):
			return "Item roll must reference one unique attached affix."
		if not _integer(roll.tier, 1) or not _number(roll.value):
			return "Item roll tier and value must be finite JSON-safe numbers."
		rolled[roll.affix_id] = true
	for socket: Variant in value.sockets:
		if not socket is String or (not socket.is_empty() and (not socket.begins_with("rune.") or not StableIdContract.is_valid(socket))):
			return "Item sockets must contain an empty string or stable rune ID."
	var budget := [4096]
	return _json_error(value.metadata, 0, budget)


static func _integer(value: Variant, minimum: int) -> bool:
	return _number(value) and value >= minimum and floor(value) == value


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= MAX_SAFE_INTEGER


static func _json_error(value: Variant, depth: int, budget: Array) -> String:
	budget[0] -= 1
	if depth > 8 or budget[0] < 0:
		return "Item metadata exceeds nesting or value-count limits."
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return ""
		TYPE_STRING:
			return "" if value.length() <= 4096 else "Item metadata string exceeds 4096 characters."
		TYPE_INT, TYPE_FLOAT:
			return "" if _number(value) else "Item metadata number must be finite and JSON-safe."
		TYPE_ARRAY, TYPE_DICTIONARY:
			if value.size() > 4096:
				return "Item metadata container exceeds 4096 entries."
			for key: Variant in value:
				if value is Dictionary and (not key is String or key.length() > 4096):
					return "Item metadata keys must be bounded strings."
				var error := _json_error(value[key] if value is Dictionary else key, depth + 1, budget)
				if not error.is_empty():
					return error
			return ""
	return "Item metadata must contain JSON primitives only."
