class_name PresentationEntitySnapshot
extends RefCounted

var _runtime_id := 0
var _definition_id := ""
var _is_player_controlled := false
var _position := Vector2.ZERO
var _movement_input := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
var _health := 0
var _max_health := 0
var _resource := 0.0
var _max_resource := 0.0
var _cast_phase := "cast.idle"
var _ability_slot := -1
var _is_configured := false


func runtime_id() -> int:
	return _runtime_id


func definition_id() -> String:
	return _definition_id


func is_player_controlled() -> bool:
	return _is_player_controlled


func position() -> Vector2:
	return _position


func movement_input() -> Vector2:
	return _movement_input


func aim_direction() -> Vector2:
	return _aim_direction


func health() -> int:
	return _health


func max_health() -> int:
	return _max_health


func resource() -> float:
	return _resource


func max_resource() -> float:
	return _max_resource


func is_alive() -> bool:
	return _health > 0


func cast_phase() -> String:
	return _cast_phase


func ability_slot() -> int:
	return _ability_slot


func to_dictionary() -> Dictionary:
	return {
		"runtime_id": _runtime_id,
		"definition_id": _definition_id,
		"is_player_controlled": _is_player_controlled,
		"position": [_position.x, _position.y],
		"movement_input": [_movement_input.x, _movement_input.y],
		"aim_direction": [_aim_direction.x, _aim_direction.y],
		"health": _health,
		"max_health": _max_health,
		"resource": _resource,
		"max_resource": _max_resource,
		"is_alive": is_alive(),
		"cast_phase": _cast_phase,
		"ability_slot": _ability_slot,
	}


func _publish(entity: RefCounted) -> void:
	if _is_configured:
		return
	_runtime_id = entity.runtime_id()
	_definition_id = entity.definition_id()
	_is_player_controlled = entity.is_player_controlled()
	_position = entity.position()
	_movement_input = entity.movement_input()
	_aim_direction = entity.aim_direction()
	_health = entity.health()
	_max_health = entity.max_health()
	_resource = entity.resource()
	_max_resource = entity.max_resource()
	_cast_phase = entity.cast_phase()
	_ability_slot = entity.ability_slot()
	_is_configured = true
