class_name AbilityEffectCommand
extends RefCounted

var _effect: Resource = null
var _source_entity_id := 0
var _target_entity_id := 0
var _target_position := Vector2.ZERO
var _direction := Vector2.ZERO
var _is_configured := false


func effect() -> Resource:
	return _effect


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func target_position() -> Vector2:
	return _target_position


func direction() -> Vector2:
	return _direction


func _configure(
	effect: Resource,
	source_entity_id: int,
	target_entity_id: int,
	target_position: Vector2,
	direction: Vector2
) -> void:
	if _is_configured:
		return
	_effect = effect
	_source_entity_id = source_entity_id
	_target_entity_id = target_entity_id
	_target_position = target_position
	_direction = direction
	_is_configured = true
