class_name KeyboardMouseCommandAdapter
extends Node

const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")

const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"

var _actor_id := 0
var _next_client_sequence := 1
var _last_movement := Vector2.ZERO
var _last_aim := Vector2.RIGHT
var _has_movement_sample := false
var _has_aim_sample := false
var _is_configured := false


func configure(actor_id_value: int, last_client_sequence: int = 0) -> String:
	if _is_configured:
		return "Keyboard/mouse command adapter is already configured."
	if actor_id_value <= 0:
		return "Command adapter actor ID must be positive."
	if last_client_sequence < 0:
		return "Command adapter client sequence must be non-negative."
	_actor_id = actor_id_value
	_next_client_sequence = last_client_sequence + 1
	_is_configured = true
	return ""


func next_client_sequence() -> int:
	return _next_client_sequence


func poll(tick: int, actor_world_position: Vector2) -> Dictionary:
	if not _is_configured:
		return _sample_error("Keyboard/mouse command adapter is not configured.")
	if not is_inside_tree() or get_viewport() == null:
		return _sample_error("Keyboard/mouse command adapter must be inside a viewport tree before polling.")
	var movement := Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)
	var viewport := get_viewport()
	var mouse_world_position: Vector2 = (
		viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	)
	return commands_from_sample(tick, movement, actor_world_position, mouse_world_position)


func commands_from_sample(
	tick: int,
	movement_sample: Vector2,
	actor_world_position: Vector2,
	mouse_world_position: Vector2
) -> Dictionary:
	if not _is_configured:
		return _sample_error("Keyboard/mouse command adapter is not configured.")
	if tick <= 0:
		return _sample_error("Command sample tick must be positive.")
	if (
		not movement_sample.is_finite()
		or not actor_world_position.is_finite()
		or not mouse_world_position.is_finite()
	):
		return _sample_error("Command sample vectors must be finite.")

	var movement := movement_sample
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	var aim_offset := mouse_world_position - actor_world_position
	var has_aim := not aim_offset.is_zero_approx()
	var aim := aim_offset.normalized() if has_aim else _last_aim
	var staged_sequence := _next_client_sequence
	var commands: Array = []

	if not _has_movement_sample or not movement.is_equal_approx(_last_movement):
		var move_command := PlayerCommandContract.new()
		var move_error: String = move_command.configure(
			tick,
			_actor_id,
			PlayerCommandContract.MOVE,
			movement,
			-1,
			staged_sequence
		)
		if not move_error.is_empty():
			return _sample_error(move_error)
		commands.append(move_command)
		staged_sequence += 1

	if has_aim and (not _has_aim_sample or not aim.is_equal_approx(_last_aim)):
		var aim_command := PlayerCommandContract.new()
		var aim_error: String = aim_command.configure(
			tick,
			_actor_id,
			PlayerCommandContract.AIM,
			aim,
			-1,
			staged_sequence
		)
		if not aim_error.is_empty():
			return _sample_error(aim_error)
		commands.append(aim_command)
		staged_sequence += 1

	_next_client_sequence = staged_sequence
	_last_movement = movement
	_has_movement_sample = true
	if has_aim:
		_last_aim = aim
		_has_aim_sample = true
	return {"commands": commands, "error": ""}


static func _sample_error(message: String) -> Dictionary:
	return {"commands": [], "error": message}
