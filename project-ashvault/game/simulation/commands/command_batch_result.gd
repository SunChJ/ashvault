class_name CommandBatchResult
extends RefCounted

var _tick := -1
var _is_success := false
var _accepted_count := 0
var _diagnostics: Array = []
var _is_configured := false


func tick() -> int:
	return _tick


func is_success() -> bool:
	return _is_success


func accepted_count() -> int:
	return _accepted_count


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func _configure(
	tick_value: int,
	is_success_value: bool,
	accepted_count_value: int,
	diagnostics_value: Array
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_is_success = is_success_value
	_accepted_count = accepted_count_value
	_diagnostics = diagnostics_value.duplicate(true)
	_is_configured = true
