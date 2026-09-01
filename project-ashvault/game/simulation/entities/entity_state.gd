class_name EntityState
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")
const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")

const CAST_IDLE := "cast.idle"
const CAST_STARTED := "cast.started"
const CAST_RELEASED := "cast.released"
const CAST_CANCELED := "cast.canceled"

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
var _cast_phase := CAST_IDLE
var _ability_slot := -1
var _is_configured := false


func configure(
	runtime_id_value: int,
	definition_id_value: String,
	is_player_controlled_value: bool,
	position_value: Vector2,
	health_value: int,
	max_health_value: int,
	resource_value: float,
	max_resource_value: float,
	aim_direction_value: Vector2 = Vector2.RIGHT
) -> String:
	if _is_configured:
		return "Entity state is immutable after configuration."
	if runtime_id_value <= 0:
		return "Runtime entity ID must be positive."
	var definition_error := StableIdContract.validation_error(definition_id_value)
	if not definition_error.is_empty():
		return definition_error
	if not position_value.is_finite():
		return "Entity position must be finite."
	if max_health_value <= 0 or health_value < 0 or health_value > max_health_value:
		return "Entity health must be between zero and a positive maximum."
	if (
		not is_finite(resource_value)
		or not is_finite(max_resource_value)
		or max_resource_value < 0.0
		or resource_value < 0.0
		or resource_value > max_resource_value
	):
		return "Entity resource must be finite and between zero and its non-negative maximum."
	if not aim_direction_value.is_finite() or aim_direction_value.is_zero_approx():
		return "Entity aim direction must be finite and non-zero."
	if aim_direction_value.length_squared() > 1.000001:
		return "Entity aim direction length must not exceed one."
	_publish(
		runtime_id_value,
		definition_id_value,
		is_player_controlled_value,
		position_value,
		Vector2.ZERO,
		aim_direction_value,
		health_value,
		max_health_value,
		resource_value,
		max_resource_value,
		CAST_IDLE,
		-1
	)
	return ""


func is_configured() -> bool:
	return _is_configured


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


func _begin_tick() -> void:
	if not _is_configured:
		return
	if _cast_phase == CAST_RELEASED or _cast_phase == CAST_CANCELED:
		_cast_phase = CAST_IDLE
		_ability_slot = -1


func _requires_tick_transition() -> bool:
	return _cast_phase == CAST_RELEASED or _cast_phase == CAST_CANCELED


func _apply_command(command: RefCounted) -> String:
	if not _is_configured or not command is PlayerCommandContract or not command.is_configured():
		return "Entity cannot apply an invalid player command."
	match command.command_type():
		PlayerCommandContract.MOVE:
			_movement_input = command.aim_vector()
		PlayerCommandContract.AIM:
			_aim_direction = command.aim_vector()
		PlayerCommandContract.CAST_START:
			if _cast_phase != CAST_IDLE:
				return "Cast start requires an idle entity."
			_cast_phase = CAST_STARTED
			_ability_slot = command.ability_slot()
			_apply_optional_aim(command.aim_vector())
		PlayerCommandContract.CAST_RELEASE:
			if _cast_phase != CAST_STARTED:
				return "Cast release requires a started cast."
			if _ability_slot != command.ability_slot():
				return "Cast release ability slot must match the started cast."
			_cast_phase = CAST_RELEASED
			_apply_optional_aim(command.aim_vector())
		PlayerCommandContract.CANCEL:
			if _cast_phase != CAST_STARTED:
				return "Cancel requires a started cast."
			_cast_phase = CAST_CANCELED
		_:
			return "Entity received an unknown player command."
	return ""


func _duplicate_state() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._publish(
		_runtime_id,
		_definition_id,
		_is_player_controlled,
		_position,
		_movement_input,
		_aim_direction,
		_health,
		_max_health,
		_resource,
		_max_resource,
		_cast_phase,
		_ability_slot
	)
	return result


func _canonical_values() -> Array:
	return [
		_runtime_id,
		_definition_id,
		_is_player_controlled,
		_position.x,
		_position.y,
		_movement_input.x,
		_movement_input.y,
		_aim_direction.x,
		_aim_direction.y,
		_health,
		_max_health,
		_resource,
		_max_resource,
		_cast_phase,
		_ability_slot,
	]


func _publish(
	runtime_id_value: int,
	definition_id_value: String,
	is_player_controlled_value: bool,
	position_value: Vector2,
	movement_input_value: Vector2,
	aim_direction_value: Vector2,
	health_value: int,
	max_health_value: int,
	resource_value: float,
	max_resource_value: float,
	cast_phase_value: String,
	ability_slot_value: int
) -> void:
	if _is_configured:
		return
	_runtime_id = runtime_id_value
	_definition_id = definition_id_value
	_is_player_controlled = is_player_controlled_value
	_position = position_value
	_movement_input = movement_input_value
	_aim_direction = aim_direction_value
	_health = health_value
	_max_health = max_health_value
	_resource = resource_value
	_max_resource = max_resource_value
	_cast_phase = cast_phase_value
	_ability_slot = ability_slot_value
	_is_configured = true


func _apply_optional_aim(value: Vector2) -> void:
	if not value.is_zero_approx():
		_aim_direction = value
