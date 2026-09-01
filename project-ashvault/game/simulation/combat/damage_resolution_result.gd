class_name DamageResolutionResult
extends RefCounted

var _result: RefCounted = null
var _errors := PackedStringArray()
var _is_configured := false


func is_success() -> bool:
	return _errors.is_empty() and _result != null


func result() -> RefCounted:
	return _result


func errors() -> PackedStringArray:
	return _errors.duplicate()


func _configure(result_value: RefCounted, errors_value: PackedStringArray) -> void:
	if _is_configured:
		return
	_result = result_value
	_errors = errors_value.duplicate()
	_is_configured = true
