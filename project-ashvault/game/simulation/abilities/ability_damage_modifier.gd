class_name AbilityDamageModifier
extends Resource

const RuntimeModifier = preload("res://game/simulation/combat/damage_modifier.gd")

var _damage_type_id := ""
var _operation := -1
var _value := 0.0
var _source_id := ""
var _target_damage_type_id := ""
var _condition_id := ""
var _priority := 0
var _is_configured := false


func configure(
	damage_type_id: String,
	operation: int,
	value: float,
	source_id: String,
	target_damage_type_id: String = "",
	condition_id: String = "",
	priority: int = 0
) -> String:
	if _is_configured:
		return "Authored damage modifier from '%s' is already configured and immutable." % _source_id
	var runtime := RuntimeModifier.new()
	var validation_error: String = runtime.configure(
		damage_type_id,
		operation,
		value,
		source_id,
		target_damage_type_id,
		condition_id,
		priority
	)
	if not validation_error.is_empty():
		return validation_error

	_damage_type_id = damage_type_id
	_operation = operation
	_value = value
	_source_id = source_id
	_target_damage_type_id = target_damage_type_id
	_condition_id = condition_id
	_priority = priority
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func identity_key() -> String:
	return "%s|%d|%s|%s|%s" % [
		_damage_type_id,
		_operation,
		_source_id,
		_target_damage_type_id,
		_condition_id,
	]


func to_runtime() -> RefCounted:
	if not _is_configured:
		return null
	var runtime := RuntimeModifier.new()
	var error: String = runtime.configure(
		_damage_type_id,
		_operation,
		_value,
		_source_id,
		_target_damage_type_id,
		_condition_id,
		_priority
	)
	assert(error.is_empty())
	return runtime
