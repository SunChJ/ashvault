class_name PresentationSnapshot
extends RefCounted

var _tick := -1
var _state_hash := ""
var _entities: Array = []
var _entities_by_id: Dictionary = {}
var _is_configured := false


func tick() -> int:
	return _tick


func state_hash() -> String:
	return _state_hash


func entities() -> Array:
	return _entities.duplicate()


func entity(runtime_id: int) -> RefCounted:
	return _entities_by_id.get(runtime_id)


func entities_as_dictionaries() -> Array:
	var result: Array = []
	for value: RefCounted in _entities:
		result.append(value.to_dictionary())
	return result


func _publish(tick_value: int, state_hash_value: String, entities_value: Array) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_state_hash = state_hash_value
	_entities = entities_value.duplicate()
	for value: RefCounted in _entities:
		_entities_by_id[value.runtime_id()] = value
	_is_configured = true
