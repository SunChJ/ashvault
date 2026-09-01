class_name AbilityExecutionResult
extends RefCounted

var _outputs: Array = []
var _errors := PackedStringArray()
var _is_configured := false


func is_success() -> bool:
	return _errors.is_empty()


func outputs() -> Array:
	return _outputs.duplicate()


func errors() -> PackedStringArray:
	return _errors.duplicate()


func _configure(outputs_value: Array, errors_value: PackedStringArray) -> void:
	if _is_configured:
		return
	_outputs = outputs_value.duplicate()
	_errors = errors_value.duplicate()
	_is_configured = true
