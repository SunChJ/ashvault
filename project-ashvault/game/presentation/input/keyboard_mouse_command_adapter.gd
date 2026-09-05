class_name KeyboardMouseCommandAdapter
extends Node

const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")

const CastBinding = preload("res://game/simulation/abilities/ability_cast_binding.gd")

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


# Combat samples include held movement every tick so cast-owned movement resets
# cannot leave a still-held movement key suppressed after recovery.
func combat_commands_from_sample(
	tick: int,
	actor: RefCounted,
	loadout: RefCounted,
	movement: Vector2,
	mouse_position: Vector2,
	pressed_slots: Array
) -> Dictionary:
	if not _is_configured or actor == null or actor.runtime_id() != _actor_id:
		return _sample_error("Combat input requires the configured actor snapshot.")
	if not movement.is_finite() or not mouse_position.is_finite() or tick <= 0:
		return _sample_error("Combat input requires finite vectors and a positive tick.")
	if not actor.is_alive():
		return {"commands": [], "error": ""}
	var phase: String = actor.cast_phase()
	if phase == "cast.canceled" or (phase == "cast.recovering" and actor.recovery_ticks_remaining() <= 1):
		phase = "cast.idle"
	if phase == "cast.released":
		phase = "cast.idle" if actor.recovery_ticks_remaining() == 0 else "cast.recovering"
	var requested := -1
	var candidates := pressed_slots.duplicate()
	for value: Variant in candidates:
		if not value is int or not loadout.has_slot(value):
			return _sample_error("Combat input contains an unknown ability slot.")
	candidates.sort()
	if candidates.has(5):
		candidates.erase(5)
		candidates.push_front(5)
	for slot: int in candidates:
		var binding: RefCounted = loadout.binding(slot)
		if actor.cooldown_ticks_remaining(slot) > 1 or actor.resource() < binding.ability().cost_amount():
			continue
		if phase == "cast.idle" or (
			phase in ["cast.started", "cast.recovering"] and binding.cancels_active_cast()
			and loadout.binding(actor.ability_slot()).allows_interruption("interrupt.ability_replaced")
		):
			requested = slot
			break
	var move := movement.limit_length(1.0)
	var release_slot := -1
	if requested >= 0:
		move = Vector2.ZERO
		if loadout.binding(requested).ability().cast_time_ticks() == 0:
			release_slot = requested
	elif phase in ["cast.started", "cast.recovering"]:
		var binding: RefCounted = loadout.binding(actor.ability_slot())
		if binding.movement_policy() == CastBinding.MovementPolicy.LOCK:
			move = Vector2.ZERO
		if phase == "cast.started" and actor.cast_ticks_remaining() <= 1 and (move.is_zero_approx() or binding.movement_policy() == CastBinding.MovementPolicy.ALLOW):
			release_slot = actor.ability_slot()
	var aim: Vector2 = actor.position().direction_to(mouse_position)
	if aim.is_zero_approx():
		aim = actor.aim_direction()
	var specs: Array = [[PlayerCommandContract.MOVE, move, -1], [PlayerCommandContract.AIM, aim, -1]]
	if requested >= 0:
		specs.append([PlayerCommandContract.CAST_START, aim, requested])
	if release_slot >= 0:
		specs.append([PlayerCommandContract.CAST_RELEASE, aim, release_slot])
	var commands: Array = []
	for spec: Array in specs:
		var command := PlayerCommandContract.new()
		var error: String = command.configure(tick, _actor_id, spec[0], spec[1], spec[2], _next_client_sequence + commands.size())
		if not error.is_empty():
			return _sample_error(error)
		commands.append(command)
	_next_client_sequence += commands.size()
	return {"commands": commands, "error": ""}
