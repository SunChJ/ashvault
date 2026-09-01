class_name DamageModifier
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

enum Operation {
	FLAT,
	INCREASED,
	MORE,
	CONVERSION,
	DEFENSE,
	RESISTANCE,
	PENETRATION,
	CONDITIONAL,
}

const OPERATION_NAMES: Array[String] = [
	"FLAT",
	"INCREASED",
	"MORE",
	"CONVERSION",
	"DEFENSE",
	"RESISTANCE",
	"PENETRATION",
	"CONDITIONAL",
]

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
		return "Damage modifier from '%s' is already configured and immutable." % _source_id
	for id_value in [damage_type_id, source_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if operation < Operation.FLAT or operation > Operation.CONDITIONAL:
		return "Unknown damage modifier operation '%s'." % operation
	if not is_finite(value):
		return "Damage modifier from '%s' must be finite." % source_id
	if operation == Operation.CONVERSION:
		var target_error := StableIdContract.validation_error(target_damage_type_id)
		if not target_error.is_empty():
			return "Conversion target: %s" % target_error
		if target_damage_type_id == damage_type_id:
			return "Conversion source and target damage types must differ."
		if value < 0.0 or value > 1.0:
			return "Conversion value must be between 0 and 1."
	elif not target_damage_type_id.is_empty():
		return "Only CONVERSION modifiers may define a target damage type."
	if operation == Operation.CONDITIONAL:
		var condition_error := StableIdContract.validation_error(condition_id)
		if not condition_error.is_empty():
			return "Conditional modifier: %s" % condition_error
	elif not condition_id.is_empty():
		return "Only CONDITIONAL modifiers may define a condition."
	if operation in [Operation.DEFENSE, Operation.PENETRATION] and value < 0.0:
		return "%s values must be non-negative." % operation_name(operation)

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


func damage_type_id() -> String:
	return _damage_type_id


func operation() -> int:
	return _operation


func amount() -> float:
	return _value


func source_id() -> String:
	return _source_id


func target_damage_type_id() -> String:
	return _target_damage_type_id


func condition_id() -> String:
	return _condition_id


func priority() -> int:
	return _priority


func identity_key() -> String:
	return "%s|%d|%s|%s|%s" % [
		_damage_type_id,
		_operation,
		_source_id,
		_target_damage_type_id,
		_condition_id,
	]


func explanation_fields() -> Dictionary:
	var result := {
		"damage_type_id": _damage_type_id,
		"operation": operation_name(_operation),
		"value": _value,
		"source_id": _source_id,
		"priority": _priority,
	}
	if not _target_damage_type_id.is_empty():
		result["target_damage_type_id"] = _target_damage_type_id
	if not _condition_id.is_empty():
		result["condition_id"] = _condition_id
	return result


static func operation_name(operation: int) -> String:
	if operation < Operation.FLAT or operation > Operation.CONDITIONAL:
		return "UNKNOWN"
	return OPERATION_NAMES[operation]
