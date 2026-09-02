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
var _snapshot_tick := -1
var _resource_id := ""
var _cast_started_tick := -1
var _cast_ready_tick := -1
var _recovery_end_tick := -1
var _cooldown_end_ticks: Dictionary = {}
var _last_cancel_reason := ""
var _has_cast_runtime := false
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


func resource_id() -> String:
	return _resource_id


func cast_ticks_remaining() -> int:
	if not _has_cast_runtime or _cast_phase != "cast.started":
		return 0
	return maxi(0, _cast_ready_tick - _snapshot_tick)


func recovery_ticks_remaining() -> int:
	if not _has_cast_runtime:
		return 0
	if _cast_phase == "cast.released":
		return maxi(0, _recovery_end_tick - _snapshot_tick - 1)
	if _cast_phase == "cast.recovering":
		return maxi(0, _recovery_end_tick - _snapshot_tick)
	return 0


func cooldown_ticks_remaining(ability_slot_value: int) -> int:
	if not _has_cast_runtime:
		return 0
	return maxi(0, int(_cooldown_end_ticks.get(ability_slot_value, 0)) - _snapshot_tick)


func cooldowns() -> Array:
	if not _has_cast_runtime:
		return []
	var result: Array = []
	var slots: Array = _cooldown_end_ticks.keys()
	slots.sort()
	for slot: int in slots:
		result.append({
			"ability_slot": slot,
			"end_tick": _cooldown_end_ticks[slot],
			"remaining_ticks": cooldown_ticks_remaining(slot),
		})
	return result


func last_cancel_reason() -> String:
	return _last_cancel_reason


func to_dictionary() -> Dictionary:
	var result := {
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
	if _has_cast_runtime:
		result["resource_id"] = _resource_id
		result["cast_started_tick"] = _cast_started_tick
		result["cast_ready_tick"] = _cast_ready_tick
		result["cast_ticks_remaining"] = cast_ticks_remaining()
		result["recovery_end_tick"] = _recovery_end_tick
		result["recovery_ticks_remaining"] = recovery_ticks_remaining()
		result["cooldowns"] = cooldowns()
		result["last_cancel_reason"] = _last_cancel_reason
	return result


func _publish(entity: RefCounted, snapshot_tick_value: int = -1) -> void:
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
	_snapshot_tick = snapshot_tick_value
	if entity.has_cast_runtime():
		_resource_id = entity.resource_id()
		_cast_started_tick = entity.cast_started_tick()
		_cast_ready_tick = entity.cast_ready_tick()
		_recovery_end_tick = entity.recovery_end_tick()
		_cooldown_end_ticks = entity.cooldown_end_ticks()
		_last_cancel_reason = entity.last_cancel_reason()
		_has_cast_runtime = true
	_is_configured = true
