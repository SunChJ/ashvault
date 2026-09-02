class_name DeliveryTarget
extends RefCounted

var _runtime_id := 0
var _team_id := 0
var _position := Vector2.ZERO
var _collision_radius := 0.0
var _is_alive := false
var _is_configured := false


func configure(
	runtime_id_value: int,
	team_id_value: int,
	position_value: Vector2,
	collision_radius_value: float,
	is_alive_value: bool = true
) -> String:
	if _is_configured:
		return "Delivery target %d is immutable." % _runtime_id
	if runtime_id_value <= 0 or team_id_value < 0:
		return "Delivery target runtime ID must be positive and team must be non-negative."
	if not position_value.is_finite():
		return "Delivery target position must be finite."
	if not is_finite(collision_radius_value) or collision_radius_value < 0.0:
		return "Delivery target collision radius must be finite and non-negative."
	_runtime_id = runtime_id_value
	_team_id = team_id_value
	_position = position_value
	_collision_radius = collision_radius_value
	_is_alive = is_alive_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func runtime_id() -> int:
	return _runtime_id


func team_id() -> int:
	return _team_id


func position() -> Vector2:
	return _position


func collision_radius() -> float:
	return _collision_radius


func is_alive() -> bool:
	return _is_alive


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_runtime_id,
		_team_id,
		_position.x,
		_position.y,
		_collision_radius,
		_is_alive,
	]
