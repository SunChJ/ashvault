class_name EnemyAttackIntent
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _tick := -1
var _source_entity_id := 0
var _target_entity_id := 0
var _attack_id := ""
var _source_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _direction := Vector2.ZERO
var _is_configured := false


func configure(
	tick_value: int,
	source_entity_id_value: int,
	target_entity_id_value: int,
	attack_id_value: String,
	source_position_value: Vector2,
	target_position_value: Vector2
) -> String:
	if _is_configured:
		return "Enemy attack intent is immutable after publication."
	if tick_value < 0:
		return "Enemy attack intent tick must be non-negative."
	if source_entity_id_value <= 0 or target_entity_id_value <= 0:
		return "Enemy attack intent entity IDs must be positive."
	var attack_error := StableIdContract.validation_error(attack_id_value)
	if not attack_error.is_empty():
		return attack_error
	if not source_position_value.is_finite() or not target_position_value.is_finite():
		return "Enemy attack intent positions must be finite."
	var displacement := target_position_value - source_position_value

	_tick = tick_value
	_source_entity_id = source_entity_id_value
	_target_entity_id = target_entity_id_value
	_attack_id = attack_id_value
	_source_position = source_position_value
	_target_position = target_position_value
	_direction = displacement.normalized() if not displacement.is_zero_approx() else Vector2.RIGHT
	_is_configured = true
	return ""


func tick() -> int:
	return _tick


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func attack_id() -> String:
	return _attack_id


func source_position() -> Vector2:
	return _source_position


func target_position() -> Vector2:
	return _target_position


func direction() -> Vector2:
	return _direction
