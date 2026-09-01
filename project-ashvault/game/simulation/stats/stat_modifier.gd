class_name StatModifier
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

enum Operation {
	BASE,
	FLAT,
	INCREASED,
	MORE,
	CONVERSION,
	OVERRIDE,
	CAP,
}

const OPERATION_NAMES: Array[String] = [
	"BASE",
	"FLAT",
	"INCREASED",
	"MORE",
	"CONVERSION",
	"OVERRIDE",
	"CAP",
]

var _stat_id := ""
var _operation := -1
var _value := 0.0
var _source_id := ""
var _condition_id := ""
var _priority := 0
var _target_stat_id := ""
var _is_configured := false


func configure(
	stat_id: String,
	operation: int,
	value: float,
	source_id: String,
	condition_id: String = "",
	priority: int = 0,
	target_stat_id: String = ""
) -> String:
	if _is_configured:
		return "Modifier from '%s' is already configured and immutable." % _source_id
	for id_value in [stat_id, source_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not condition_id.is_empty():
		var condition_error := StableIdContract.validation_error(condition_id)
		if not condition_error.is_empty():
			return condition_error
	if operation < Operation.BASE or operation > Operation.CAP:
		return "Unknown modifier operation '%s'." % operation
	if not is_finite(value):
		return "Modifier value from '%s' must be finite." % source_id
	if operation == Operation.CONVERSION:
		var target_error := StableIdContract.validation_error(target_stat_id)
		if not target_error.is_empty():
			return "Conversion target: %s" % target_error
		if target_stat_id == stat_id:
			return "Conversion source and target stat must differ."
		if value < 0.0 or value > 1.0:
			return "Conversion value must be between 0 and 1."
	elif not target_stat_id.is_empty():
		return "Only CONVERSION modifiers may define a target stat."

	_stat_id = stat_id
	_operation = operation
	_value = value
	_source_id = source_id
	_condition_id = condition_id
	_priority = priority
	_target_stat_id = target_stat_id
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func stat_id() -> String:
	return _stat_id


func operation() -> int:
	return _operation


func amount() -> float:
	return _value


func source_id() -> String:
	return _source_id


func condition_id() -> String:
	return _condition_id


func priority() -> int:
	return _priority


func target_stat_id() -> String:
	return _target_stat_id


func identity_key() -> String:
	return "%s|%d|%s|%s" % [_stat_id, _operation, _source_id, _condition_id]


func explanation_fields() -> Dictionary:
	var result := {
		"source_id": _source_id,
		"operation": operation_name(_operation),
		"value": _value,
		"condition_id": _condition_id,
		"priority": _priority,
	}
	if _operation == Operation.CONVERSION:
		result["target_stat_id"] = _target_stat_id
	return result


static func operation_name(operation: int) -> String:
	if operation < Operation.BASE or operation > Operation.CAP:
		return "UNKNOWN"
	return OPERATION_NAMES[operation]
