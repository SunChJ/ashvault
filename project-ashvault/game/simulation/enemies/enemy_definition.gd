class_name EnemyDefinition
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")
const CANONICAL_SCHEMA_VERSION := 1

var _definition_id := ""
var _acquisition_range := 0.0
var _movement_speed_per_second := 0.0
var _collision_radius := 0.0
var _attack_range := 0.0
var _attack_cooldown_ticks := 0
var _attack_id := ""
var _is_configured := false


func configure(
	definition_id_value: String,
	acquisition_range_value: float,
	movement_speed_per_second_value: float,
	collision_radius_value: float,
	attack_range_value: float,
	attack_cooldown_ticks_value: int,
	attack_id_value: String
) -> String:
	if _is_configured:
		return "Enemy definition '%s' is immutable after configuration." % _definition_id
	for id_value: String in [definition_id_value, attack_id_value]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not is_finite(acquisition_range_value) or acquisition_range_value <= 0.0:
		return "Enemy acquisition range must be finite and positive."
	if not is_finite(movement_speed_per_second_value) or movement_speed_per_second_value <= 0.0:
		return "Enemy movement speed must be finite and positive."
	if not is_finite(collision_radius_value) or collision_radius_value < 0.0:
		return "Enemy collision radius must be finite and non-negative."
	if not is_finite(attack_range_value) or attack_range_value < 0.0:
		return "Enemy attack range must be finite and non-negative."
	if attack_cooldown_ticks_value <= 0:
		return "Enemy attack cooldown must contain at least one tick."

	_definition_id = definition_id_value
	_acquisition_range = acquisition_range_value
	_movement_speed_per_second = movement_speed_per_second_value
	_collision_radius = collision_radius_value
	_attack_range = attack_range_value
	_attack_cooldown_ticks = attack_cooldown_ticks_value
	_attack_id = attack_id_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func definition_id() -> String:
	return _definition_id


func acquisition_range() -> float:
	return _acquisition_range


func movement_speed_per_second() -> float:
	return _movement_speed_per_second


func collision_radius() -> float:
	return _collision_radius


func attack_range() -> float:
	return _attack_range


func attack_cooldown_ticks() -> int:
	return _attack_cooldown_ticks


func attack_id() -> String:
	return _attack_id


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		CANONICAL_SCHEMA_VERSION,
		_definition_id,
		_acquisition_range,
		_movement_speed_per_second,
		_collision_radius,
		_attack_range,
		_attack_cooldown_ticks,
		_attack_id,
	]
