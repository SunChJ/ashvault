class_name PlayerCommand
extends RefCounted

const MOVE := "command.move"
const AIM := "command.aim"
const CAST_START := "command.cast_start"
const CAST_RELEASE := "command.cast_release"
const CANCEL := "command.cancel"
const SUPPORTED_TYPES := [MOVE, AIM, CAST_START, CAST_RELEASE, CANCEL]
const DTO_FIELDS := [
	"ability_slot",
	"actor_id",
	"aim_vector",
	"client_sequence",
	"command_type",
	"tick",
]

var _tick := -1
var _actor_id := 0
var _command_type := ""
var _aim_vector := Vector2.ZERO
var _ability_slot := -1
var _client_sequence := 0
var _is_configured := false


func configure(
	tick_value: int,
	actor_id_value: int,
	command_type_value: String,
	aim_vector_value: Vector2,
	ability_slot_value: int,
	client_sequence_value: int
) -> String:
	if _is_configured:
		return "Player command is immutable after configuration."
	if tick_value <= 0:
		return "Player command tick must be positive."
	if actor_id_value <= 0:
		return "Player command actor ID must be positive."
	if not SUPPORTED_TYPES.has(command_type_value):
		return "Unknown player command '%s'." % command_type_value
	if not aim_vector_value.is_finite():
		return "Player command aim vector must be finite."
	if aim_vector_value.length_squared() > 1.000001:
		return "Player command aim vector length must not exceed one."
	if client_sequence_value <= 0:
		return "Player command client sequence must be positive."

	match command_type_value:
		MOVE:
			if ability_slot_value != -1:
				return "Movement commands cannot specify an ability slot."
		AIM:
			if ability_slot_value != -1:
				return "Aim commands cannot specify an ability slot."
			if aim_vector_value.is_zero_approx():
				return "Aim commands require a non-zero direction."
		CAST_START, CAST_RELEASE:
			if ability_slot_value < 0:
				return "Cast commands require a non-negative ability slot."
		CANCEL:
			if ability_slot_value != -1:
				return "Cancel commands cannot specify an ability slot."
			if not aim_vector_value.is_zero_approx():
				return "Cancel commands cannot specify an aim vector."

	_tick = tick_value
	_actor_id = actor_id_value
	_command_type = command_type_value
	_aim_vector = aim_vector_value
	_ability_slot = ability_slot_value
	_client_sequence = client_sequence_value
	_is_configured = true
	return ""


func configure_from_dictionary(value: Dictionary) -> String:
	if _is_configured:
		return "Player command is immutable after configuration."
	var fields: Array = value.keys()
	fields.sort()
	if fields != DTO_FIELDS:
		return "Player command DTO must contain exactly: %s." % [DTO_FIELDS]
	var integer_fields := ["tick", "actor_id", "ability_slot", "client_sequence"]
	var integers: Dictionary = {}
	for field: String in integer_fields:
		var parsed := _parse_integer(value[field], field)
		if not parsed["error"].is_empty():
			return parsed["error"]
		integers[field] = parsed["value"]
	if not value["command_type"] is String:
		return "Player command type must be a String."
	var vector_value: Variant = value["aim_vector"]
	if not vector_value is Array or vector_value.size() != 2:
		return "Player command aim vector must be a two-number Array."
	for component: Variant in vector_value:
		if not component is int and not component is float:
			return "Player command aim vector must contain only numbers."
		if not is_finite(float(component)):
			return "Player command aim vector must be finite."
	return configure(
		integers["tick"],
		integers["actor_id"],
		value["command_type"],
		Vector2(float(vector_value[0]), float(vector_value[1])),
		integers["ability_slot"],
		integers["client_sequence"]
	)


func is_configured() -> bool:
	return _is_configured


func tick() -> int:
	return _tick


func actor_id() -> int:
	return _actor_id


func command_type() -> String:
	return _command_type


func aim_vector() -> Vector2:
	return _aim_vector


func ability_slot() -> int:
	return _ability_slot


func client_sequence() -> int:
	return _client_sequence


func to_dictionary() -> Dictionary:
	if not _is_configured:
		return {}
	return {
		"tick": _tick,
		"actor_id": _actor_id,
		"command_type": _command_type,
		"aim_vector": [_aim_vector.x, _aim_vector.y],
		"ability_slot": _ability_slot,
		"client_sequence": _client_sequence,
	}


static func _parse_integer(value: Variant, field: String) -> Dictionary:
	if not value is int and not value is float:
		return {"value": 0, "error": "Player command %s must be an integer." % field}
	var numeric := float(value)
	if not is_finite(numeric) or numeric != floor(numeric):
		return {"value": 0, "error": "Player command %s must be an integer." % field}
	return {"value": int(numeric), "error": ""}
