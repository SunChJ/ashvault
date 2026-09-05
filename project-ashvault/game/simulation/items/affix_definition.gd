class_name AffixDefinition
extends "res://game/content/content_definition.gd"

const Modifier = preload("res://game/simulation/stats/stat_modifier.gd")
const Tier = preload("res://game/simulation/items/affix_tier.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")

var _group_id: String = ""
var _stat_id: String = ""
var _allowed_slots: Array[String] = []
var _allowed_bases: Array[String] = []
var _excluded_affixes: Array[String] = []
var _tiers: Array[Resource] = []

@export var group_id: String:
	get:
		return _group_id
	set(value):
		if not is_frozen():
			_group_id = value

@export var stat_id: String:
	get:
		return _stat_id
	set(value):
		if not is_frozen():
			_stat_id = value

@export var allowed_slots: Array[String]:
	get:
		return _allowed_slots.duplicate()
	set(value):
		if not is_frozen():
			_allowed_slots = value.duplicate()

@export var allowed_bases: Array[String]:
	get:
		return _allowed_bases.duplicate()
	set(value):
		if not is_frozen():
			_allowed_bases = value.duplicate()

@export var excluded_affixes: Array[String]:
	get:
		return _excluded_affixes.duplicate()
	set(value):
		if not is_frozen():
			_excluded_affixes = value.duplicate()

@export var tiers: Array[Resource]:
	get:
		return _tiers.duplicate()
	set(value):
		if not is_frozen():
			_tiers = value.duplicate()


var _operation: int = Modifier.Operation.FLAT
var _condition_id: String = ""
var _priority: int = 0
var _target_stat_id: String = ""

@export var operation: int:
	get:
		return _operation
	set(value):
		if not is_frozen():
			_operation = value

@export var condition_id: String:
	get:
		return _condition_id
	set(value):
		if not is_frozen():
			_condition_id = value

@export var priority: int:
	get:
		return _priority
	set(value):
		if not is_frozen():
			_priority = value

@export var target_stat_id: String:
	get:
		return _target_stat_id
	set(value):
		if not is_frozen():
			_target_stat_id = value


func validation_error() -> String:
	for pair: Array in [[content_id, "affix."], [group_id, "affix_group."], [stat_id, "stat."]]:
		if not pair[0].begins_with(pair[1]) or not StableIdContract.is_valid(pair[0]):
			return "Affix identity, group, or stat ID is invalid."
	if allowed_slots.is_empty() or tiers.is_empty() or tiers.size() > 5:
		return "Affix requires slots and one to five tiers."
	for pair: Array in [[allowed_slots, "slot."], [allowed_bases, "item."], [excluded_affixes, "affix."]]:
		var seen: Dictionary = {}
		for value: String in pair[0]:
			if not value.begins_with(pair[1]) or not StableIdContract.is_valid(value) or seen.has(value):
				return "Affix restrictions must contain unique stable IDs."
			seen[value] = true
	if excluded_affixes.has(content_id):
		return "Affix cannot exclude itself."
	var previous := 0
	var previous_level := 0
	for tier: Resource in tiers:
		if not tier is Tier or tier.is_frozen():
			return "Affix requires unpublished AffixTier Resources."
		var error: String = tier.validation_error()
		if not error.is_empty():
			return error
		if tier.number <= previous or tier.minimum_level < previous_level:
			return "Affix tiers must have increasing numbers and non-decreasing level gates."
		for amount: float in [tier.minimum, tier.maximum]:
			var modifier_error: String = modifier(amount, "equipment.validation").error
			if not modifier_error.is_empty():
				return modifier_error
		previous = tier.number
		previous_level = tier.minimum_level
	return ""


func freeze() -> void:
	for tier: Resource in _tiers:
		tier.freeze()
	super.freeze()


func eligible_tiers(level: int, ceiling: int) -> Array[Resource]:
	var result: Array[Resource] = []
	for tier: Resource in _tiers:
		if tier.minimum_level <= level and tier.number <= ceiling:
			result.append(tier)
	return result


func supports(definition: Resource) -> bool:
	return _allowed_slots.has(definition.equipment_slot) and (_allowed_bases.is_empty() or _allowed_bases.has(definition.content_id))


func conflicts(other: Resource) -> bool:
	return group_id == other.group_id or excluded_affixes.has(other.content_id) or other.excluded_affixes.has(content_id)


func modifier(amount: float, source_id: String) -> Dictionary:
	var result := Modifier.new()
	var error: String = result.configure(stat_id, operation, amount, source_id, condition_id, priority, target_stat_id)
	return {"modifier": result if error.is_empty() else null, "error": error}
