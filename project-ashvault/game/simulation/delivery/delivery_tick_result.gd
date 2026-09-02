class_name DeliveryTickResult
extends RefCounted

var _tick := -1
var _is_success := false
var _hits: Array = []
var _spawned_runtime_ids: Array = []
var _expired_runtime_ids: Array = []
var _active_count := 0
var _diagnostics: Array = []
var _is_configured := false


func tick() -> int:
	return _tick


func is_success() -> bool:
	return _is_success


func hits() -> Array:
	return _hits.duplicate()


func spawned_runtime_ids() -> Array:
	return _spawned_runtime_ids.duplicate()


func expired_runtime_ids() -> Array:
	return _expired_runtime_ids.duplicate()


func active_count() -> int:
	return _active_count


func diagnostics() -> Array:
	return _diagnostics.duplicate(true)


func _configure(
	tick_value: int,
	is_success_value: bool,
	hits_value: Array,
	spawned_runtime_ids_value: Array,
	expired_runtime_ids_value: Array,
	active_count_value: int,
	diagnostics_value: Array
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_is_success = is_success_value
	_hits = hits_value.duplicate()
	_spawned_runtime_ids = spawned_runtime_ids_value.duplicate()
	_expired_runtime_ids = expired_runtime_ids_value.duplicate()
	_active_count = active_count_value
	_diagnostics = diagnostics_value.duplicate(true)
	_is_configured = true
