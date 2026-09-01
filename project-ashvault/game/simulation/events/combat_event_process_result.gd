class_name CombatEventProcessResult
extends RefCounted

var _tick := -1
var _is_success := false
var _processed_events: Array = []
var _diagnostics: Array = []
var _pending_count := 0
var _is_configured := false


func tick() -> int:
	return _tick


func is_success() -> bool:
	return _is_success


func processed_events() -> Array:
	return _processed_events.duplicate()


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func pending_count() -> int:
	return _pending_count


func is_drained() -> bool:
	return _pending_count == 0


func _configure(
	tick_value: int,
	is_success_value: bool,
	processed_events_value: Array,
	diagnostics_value: Array,
	pending_count_value: int
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_is_success = is_success_value
	_processed_events = processed_events_value.duplicate()
	_diagnostics = diagnostics_value.duplicate(true)
	_pending_count = pending_count_value
	_is_configured = true
