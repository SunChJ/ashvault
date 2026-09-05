class_name StatModifierTemplate
extends Resource

const Modifier = preload("res://game/simulation/stats/stat_modifier.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
var _frozen := false

var _effect_id: String = ""
var _stat_id: String = ""
var _operation: int = Modifier.Operation.FLAT
var _amount: float = 0.0
var _condition_id: String = ""
var _priority: int = 0
var _target_stat_id: String = ""

@export var effect_id: String:
	get:
		return _effect_id
	set(value):
		if not is_frozen():
			_effect_id = value

@export var stat_id: String:
	get:
		return _stat_id
	set(value):
		if not is_frozen():
			_stat_id = value

@export var operation: int:
	get:
		return _operation
	set(value):
		if not is_frozen():
			_operation = value

@export var amount: float:
	get:
		return _amount
	set(value):
		if not is_frozen():
			_amount = value

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


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true


func validation_error() -> String:
	if not effect_id.begins_with(_effect_prefix()) or not StableIdContract.is_valid(effect_id):
		return "Stat modifier template requires a stable effect ID with its declared prefix."
	return modifier("equipment.validation").error


func modifier(source_id: String, amount_multiplier: float = 1.0) -> Dictionary:
	var result := Modifier.new()
	var error: String = result.configure(stat_id, operation, amount * amount_multiplier, source_id, condition_id, priority, target_stat_id)
	return {"modifier": result if error.is_empty() else null, "error": error}


static func list_error(effects: Array) -> String:
	var seen: Dictionary = {}
	for effect: Variant in effects:
		if not effect is StatModifierTemplate:
			return "Contributions require StatModifierTemplate Resources."
		var error: String = effect.validation_error()
		if not error.is_empty():
			return error
		if seen.has(effect.effect_id):
			return "Stat modifier effect IDs must be unique within their source."
		seen[effect.effect_id] = true
	return ""


func _effect_prefix() -> String:
	return "stat_effect."
