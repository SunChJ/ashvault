class_name StatusTickResult
extends RefCounted

var _tick := -1
var _is_success := false
var _changes: Array = []
var _events: Array = []
var _active_count := 0
var _diagnostics: Array = []
var _is_configured := false


func tick() -> int:
	return _tick


func is_success() -> bool:
	return _is_success


func changes() -> Array:
	return _changes.duplicate()


func events() -> Array:
	return _events.duplicate()


func active_count() -> int:
	return _active_count


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func _configure(
	tick_value: int,
	is_success_value: bool,
	changes_value: Array,
	events_value: Array,
	active_count_value: int,
	diagnostics_value: Array
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_is_success = is_success_value
	_changes = changes_value.duplicate()
	_events = events_value.duplicate()
	_active_count = active_count_value
	_diagnostics = diagnostics_value.duplicate(true)
	_is_configured = true
