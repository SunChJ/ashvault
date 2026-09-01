class_name StatResolutionResult
extends RefCounted

var _snapshot: RefCounted = null
var _errors := PackedStringArray()
var _is_configured := false


func is_success() -> bool:
	return _errors.is_empty() and _snapshot != null


func snapshot() -> RefCounted:
	return _snapshot


func errors() -> PackedStringArray:
	return _errors.duplicate()


func _configure(snapshot_value: RefCounted, errors_value: PackedStringArray) -> void:
	if _is_configured:
		return
	_snapshot = snapshot_value
	_errors = errors_value.duplicate()
	_is_configured = true
