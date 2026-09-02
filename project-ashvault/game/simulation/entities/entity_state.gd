class_name EntityState
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")
const AbilityCastBindingContract = preload(
	"res://game/simulation/abilities/ability_cast_binding.gd"
)
const AbilityLoadoutContract = preload(
	"res://game/simulation/abilities/ability_loadout.gd"
)
const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")
const DamageResultContract = preload("res://game/simulation/combat/damage_result.gd")

const CAST_IDLE := "cast.idle"
const CAST_STARTED := "cast.started"
const CAST_RELEASED := "cast.released"
const CAST_CANCELED := "cast.canceled"
const CAST_RECOVERING := "cast.recovering"

const INTERRUPT_ABILITY_REPLACED := "interrupt.ability_replaced"
const INTERRUPT_DEATH := "interrupt.death"
const INTERRUPT_MANUAL := "interrupt.manual"
const INTERRUPT_MOVEMENT := "interrupt.movement"

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
var _resource_id := ""
var _cast_started_tick := -1
var _cast_ready_tick := -1
var _recovery_end_tick := -1
var _cooldown_end_ticks: Dictionary = {}
var _last_cancel_reason := ""
var _has_cast_runtime := false
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


func has_cast_runtime() -> bool:
	return _has_cast_runtime


func resource_id() -> String:
	return _resource_id


func cast_started_tick() -> int:
	return _cast_started_tick


func cast_ready_tick() -> int:
	return _cast_ready_tick


func recovery_end_tick() -> int:
	return _recovery_end_tick


func cooldown_end_ticks() -> Dictionary:
	return _cooldown_end_ticks.duplicate()


func last_cancel_reason() -> String:
	return _last_cancel_reason


func _begin_tick(current_tick: int = -1) -> void:
	if not _is_configured:
		return
	if not _has_cast_runtime:
		if _cast_phase == CAST_RELEASED or _cast_phase == CAST_CANCELED:
			_cast_phase = CAST_IDLE
			_ability_slot = -1
		return
	match _cast_phase:
		CAST_CANCELED:
			_reset_cast_to_idle()
		CAST_RELEASED:
			if current_tick >= _recovery_end_tick:
				_reset_cast_to_idle()
			else:
				_cast_phase = CAST_RECOVERING
		CAST_RECOVERING:
			if current_tick >= _recovery_end_tick:
				_reset_cast_to_idle()


func _requires_tick_transition(current_tick: int = -1) -> bool:
	if _cast_phase == CAST_RELEASED or _cast_phase == CAST_CANCELED:
		return true
	return (
		_has_cast_runtime
		and _cast_phase == CAST_RECOVERING
		and current_tick >= _recovery_end_tick
	)


func _apply_command(
	command: RefCounted,
	current_tick: int = -1,
	loadout: Variant = null
) -> String:
	if not _is_configured or not command is PlayerCommandContract or not command.is_configured():
		return "Entity cannot apply an invalid player command."
	if not is_alive():
		return "Dead entities cannot execute player commands."
	if _has_cast_runtime:
		if current_tick < 0:
			return "Cast runtime commands require a non-negative simulation tick."
		if not loadout is AbilityLoadoutContract or not loadout.is_configured():
			return "Cast runtime commands require a configured ability loadout."
		return _apply_runtime_command(command, current_tick, loadout)
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


func _apply_damage_result(result: RefCounted) -> String:
	if not result is DamageResultContract or not result.is_configured():
		return "Entity cannot apply an invalid DamageResult."
	if result.target_entity_id() != _runtime_id:
		return "Damage result target does not match runtime entity %d." % _runtime_id
	_health = maxi(0, _health - result.committed_amount())
	if _health == 0 and _has_cast_runtime and (
		_cast_phase == CAST_STARTED or _cast_phase == CAST_RECOVERING
	):
		_cancel_cast(INTERRUPT_DEATH)
	return ""


func _apply_position(value: Vector2) -> String:
	if not _is_configured:
		return "Entity position cannot change before configuration."
	if not value.is_finite():
		return "Entity position must be finite."
	_position = value
	return ""


func _configure_cast_runtime(loadout: Variant) -> String:
	if not _is_configured:
		return "Entity cast runtime requires a configured entity."
	if _has_cast_runtime:
		return "Entity cast runtime is already configured."
	if not loadout is AbilityLoadoutContract or not loadout.is_configured():
		return "Entity cast runtime requires a configured ability loadout."
	_resource_id = loadout.resource_id()
	for slot: int in loadout.slots():
		_cooldown_end_ticks[slot] = 0
	_has_cast_runtime = true
	return ""


func _apply_interruption(reason_id: String, loadout: RefCounted) -> bool:
	if not _has_cast_runtime or (
		_cast_phase != CAST_STARTED and _cast_phase != CAST_RECOVERING
	):
		return false
	var binding: RefCounted = loadout.binding(_ability_slot)
	if binding == null or not binding.allows_interruption(reason_id):
		return false
	_cancel_cast(reason_id)
	return true


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
	if _has_cast_runtime:
		result._publish_cast_runtime(
			_resource_id,
			_cast_started_tick,
			_cast_ready_tick,
			_recovery_end_tick,
			_cooldown_end_ticks,
			_last_cancel_reason
		)
	return result


func _canonical_values() -> Array:
	var result := [
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
	if _has_cast_runtime:
		var cooldown_values: Array = []
		var slots: Array = _cooldown_end_ticks.keys()
		slots.sort()
		for slot: int in slots:
			cooldown_values.append([slot, _cooldown_end_ticks[slot]])
		result.append([
			1,
			_resource_id,
			_cast_started_tick,
			_cast_ready_tick,
			_recovery_end_tick,
			cooldown_values,
			_last_cancel_reason,
		])
	return result


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


func _publish_cast_runtime(
	resource_id_value: String,
	cast_started_tick_value: int,
	cast_ready_tick_value: int,
	recovery_end_tick_value: int,
	cooldown_end_ticks_value: Dictionary,
	last_cancel_reason_value: String
) -> void:
	if not _is_configured or _has_cast_runtime:
		return
	_resource_id = resource_id_value
	_cast_started_tick = cast_started_tick_value
	_cast_ready_tick = cast_ready_tick_value
	_recovery_end_tick = recovery_end_tick_value
	_cooldown_end_ticks = cooldown_end_ticks_value.duplicate()
	_last_cancel_reason = last_cancel_reason_value
	_has_cast_runtime = true


func _apply_optional_aim(value: Vector2) -> void:
	if not value.is_zero_approx():
		_aim_direction = value


func _apply_runtime_command(
	command: RefCounted,
	current_tick: int,
	loadout: RefCounted
) -> String:
	match command.command_type():
		PlayerCommandContract.MOVE:
			return _apply_runtime_movement(command.aim_vector(), loadout)
		PlayerCommandContract.AIM:
			_aim_direction = command.aim_vector()
			return ""
		PlayerCommandContract.CAST_START:
			return _start_cast(command, current_tick, loadout)
		PlayerCommandContract.CAST_RELEASE:
			return _release_cast(command, current_tick, loadout)
		PlayerCommandContract.CANCEL:
			return _manually_cancel_cast(loadout)
		_:
			return "Entity received an unknown player command."


func _apply_runtime_movement(value: Vector2, loadout: RefCounted) -> String:
	if not value.is_zero_approx() and _cast_phase in [CAST_STARTED, CAST_RELEASED, CAST_RECOVERING]:
		var binding: RefCounted = loadout.binding(_ability_slot)
		if binding == null:
			return "Active cast has no ability binding."
		match binding.movement_policy():
			AbilityCastBindingContract.MovementPolicy.LOCK:
				return "Active cast locks movement."
			AbilityCastBindingContract.MovementPolicy.CANCEL_CAST:
				if _cast_phase == CAST_RELEASED:
					return "Released casts cannot be canceled by movement."
				_cancel_cast(INTERRUPT_MOVEMENT)
	_movement_input = value
	return ""


func _start_cast(command: RefCounted, current_tick: int, loadout: RefCounted) -> String:
	var next_binding: RefCounted = loadout.binding(command.ability_slot())
	if next_binding == null:
		return "Ability slot %d is not present in the actor loadout." % command.ability_slot()
	var replacement_reason := ""
	if _cast_phase != CAST_IDLE:
		if (
			_cast_phase != CAST_STARTED and _cast_phase != CAST_RECOVERING
			or not next_binding.cancels_active_cast()
		):
			return "Cast start requires idle state or a cancelable active cast."
		var active_binding: RefCounted = loadout.binding(_ability_slot)
		if (
			active_binding == null
			or not active_binding.allows_interruption(INTERRUPT_ABILITY_REPLACED)
		):
			return "Active cast does not allow ability replacement."
		replacement_reason = INTERRUPT_ABILITY_REPLACED

	var availability_error := _cast_availability_error(next_binding, current_tick)
	if not availability_error.is_empty():
		return availability_error
	_cast_phase = CAST_STARTED
	_ability_slot = command.ability_slot()
	_cast_started_tick = current_tick
	_cast_ready_tick = current_tick + next_binding.ability().cast_time_ticks()
	_recovery_end_tick = -1
	_last_cancel_reason = replacement_reason
	_apply_optional_aim(command.aim_vector())
	if next_binding.movement_policy() != AbilityCastBindingContract.MovementPolicy.ALLOW:
		_movement_input = Vector2.ZERO
	return ""


func _release_cast(command: RefCounted, current_tick: int, loadout: RefCounted) -> String:
	if _cast_phase != CAST_STARTED:
		return "Cast release requires a started cast."
	if _ability_slot != command.ability_slot():
		return "Cast release ability slot must match the started cast."
	if current_tick < _cast_ready_tick:
		return "Cast is not ready until tick %d." % _cast_ready_tick
	var binding: RefCounted = loadout.binding(_ability_slot)
	if binding == null:
		return "Active cast has no ability binding."
	var availability_error := _cast_availability_error(binding, current_tick)
	if not availability_error.is_empty():
		return availability_error
	var ability: Resource = binding.ability()
	_resource -= ability.cost_amount()
	_cooldown_end_ticks[_ability_slot] = current_tick + ability.cooldown_ticks()
	_cast_phase = CAST_RELEASED
	_recovery_end_tick = current_tick + ability.recovery_ticks() + 1
	_apply_optional_aim(command.aim_vector())
	return ""


func _manually_cancel_cast(loadout: RefCounted) -> String:
	if _cast_phase != CAST_STARTED and _cast_phase != CAST_RECOVERING:
		return "Manual cancellation requires a started or recovering cast."
	var binding: RefCounted = loadout.binding(_ability_slot)
	if binding == null or not binding.manual_cancel_allowed():
		return "Active cast does not allow manual cancellation."
	_cancel_cast(INTERRUPT_MANUAL)
	return ""


func _cast_availability_error(binding: RefCounted, current_tick: int) -> String:
	var slot: int = binding.ability_slot()
	var cooldown_end_tick: int = _cooldown_end_ticks.get(slot, 0)
	if current_tick < cooldown_end_tick:
		return "Ability slot %d is on cooldown until tick %d." % [slot, cooldown_end_tick]
	var cost: float = binding.ability().cost_amount()
	if _resource < cost:
		return "Ability slot %d requires %s resource; actor has %s." % [slot, cost, _resource]
	return ""


func _cancel_cast(reason_id: String) -> void:
	_cast_phase = CAST_CANCELED
	_last_cancel_reason = reason_id
	_recovery_end_tick = -1


func _reset_cast_to_idle() -> void:
	_cast_phase = CAST_IDLE
	_ability_slot = -1
	_cast_started_tick = -1
	_cast_ready_tick = -1
	_recovery_end_tick = -1
	_last_cancel_reason = ""
