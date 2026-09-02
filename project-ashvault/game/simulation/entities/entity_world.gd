class_name EntityWorld
extends RefCounted

const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")
const AbilityLoadoutContract = preload(
	"res://game/simulation/abilities/ability_loadout.gd"
)
const CastInterruptionContract = preload(
	"res://game/simulation/abilities/cast_interruption.gd"
)
const CommandResult = preload("res://game/simulation/commands/command_batch_result.gd")
const DamageResultContract = preload("res://game/simulation/combat/damage_result.gd")
const EntityStateContract = preload("res://game/simulation/entities/entity_state.gd")
const MovementEnvironmentContract = preload("res://game/simulation/movement/movement_environment.gd")
const EntitySnapshot = preload("res://game/simulation/snapshots/presentation_entity_snapshot.gd")
const Snapshot = preload("res://game/simulation/snapshots/presentation_snapshot.gd")

const FIXED_TICKS_PER_SECOND := 60
const FIXED_DELTA_SECONDS := 1.0 / float(FIXED_TICKS_PER_SECOND)
const STATE_HASH_SCHEMA_VERSION := 1
const MOVEMENT_STATE_HASH_SCHEMA_VERSION := 2
const CAST_STATE_HASH_SCHEMA_VERSION := 3

var _tick := -1
var _entities: Dictionary = {}
var _last_client_sequences: Dictionary = {}
var _movement_environment: RefCounted = null
var _ability_loadouts: Dictionary = {}
var _state_hash := ""
var _is_configured := false


func configure(
	initial_entities: Array,
	initial_tick: int = 0,
	movement_environment: Variant = null,
	ability_loadouts: Dictionary = {}
) -> String:
	if _is_configured:
		return "Entity world is already configured."
	if initial_tick < 0:
		return "Entity world initial tick must be non-negative."
	if movement_environment != null and (
		not movement_environment is MovementEnvironmentContract
		or not movement_environment.is_configured()
	):
		return "Entity world movement environment must be a configured MovementEnvironment."
	var staged_entities: Dictionary = {}
	for value: Variant in initial_entities:
		if not value is EntityStateContract or not value.is_configured():
			return "Every initial entity must be a configured EntityState."
		var runtime_id: int = value.runtime_id()
		if staged_entities.has(runtime_id):
			return "Duplicate runtime entity ID %d." % runtime_id
		if movement_environment != null:
			var placement_error: String = movement_environment.placement_error(value.position())
			if not placement_error.is_empty():
				return "Entity %d has invalid movement placement: %s" % [runtime_id, placement_error]
		staged_entities[runtime_id] = value._duplicate_state()
	var staged_loadouts: Dictionary = {}
	var actor_ids: Array = ability_loadouts.keys()
	for actor_id_value: Variant in actor_ids:
		if not actor_id_value is int or actor_id_value <= 0:
			return "Ability loadout actor IDs must be positive integers."
	actor_ids.sort()
	for actor_id_value: Variant in actor_ids:
		var actor_id: int = actor_id_value
		if not staged_entities.has(actor_id):
			return "Ability loadout actor %d does not exist." % actor_id
		var loadout: Variant = ability_loadouts[actor_id]
		if not loadout is AbilityLoadoutContract or not loadout.is_configured():
			return "Actor %d requires a configured AbilityLoadout." % actor_id
		var staged_loadout: RefCounted = loadout._duplicate_value()
		var cast_error: String = staged_entities[actor_id]._configure_cast_runtime(staged_loadout)
		if not cast_error.is_empty():
			return "Actor %d cast runtime is invalid: %s" % [actor_id, cast_error]
		staged_loadouts[actor_id] = staged_loadout
	_tick = initial_tick
	_entities = staged_entities
	_movement_environment = (
		movement_environment._duplicate_value() if movement_environment != null else null
	)
	_ability_loadouts = staged_loadouts
	for runtime_id: int in _sorted_entity_ids():
		if _entities[runtime_id].is_player_controlled():
			_last_client_sequences[runtime_id] = 0
	_state_hash = ""
	_is_configured = true
	return ""


func tick() -> int:
	return _tick


func state_hash() -> String:
	if _is_configured and _state_hash.is_empty():
		_state_hash = _compute_state_hash()
	return _state_hash


func entity_count() -> int:
	return _entities.size()


func entity_state(runtime_id: int) -> RefCounted:
	var value: Variant = _entities.get(runtime_id)
	if value == null:
		return null
	return value._duplicate_state()


func advance_tick(
	commands: Array,
	damage_results: Array = [],
	cast_interruptions: Array = []
) -> RefCounted:
	var expected_tick := _tick + 1
	if not _is_configured:
		return _rejected(
			expected_tick,
			"world.unconfigured",
			null,
			"Entity world is not configured."
		)
	var sorted_commands: Array = commands.duplicate()
	for value: Variant in sorted_commands:
		if not value is PlayerCommandContract or not value.is_configured():
			return _rejected(
				expected_tick,
				"command.invalid",
				null,
				"Command batches may contain only configured PlayerCommand values."
			)
	for value: Variant in damage_results:
		if not value is DamageResultContract or not value.is_configured():
			return _rejected_damage(
				expected_tick,
				"damage.invalid_result",
				null,
				"Entity ticks may commit only configured DamageResult values."
			)
	for value: Variant in cast_interruptions:
		if not value is CastInterruptionContract or not value.is_configured():
			return _rejected_interruption(
				expected_tick,
				"cast.invalid_interruption",
				value,
				"Entity ticks may contain only configured CastInterruption values."
			)
	sorted_commands.sort_custom(_command_precedes)
	var sorted_interruptions: Array = cast_interruptions.duplicate()
	sorted_interruptions.sort_custom(_interruption_precedes)

	var staged_entities := _entities.duplicate()
	var staged_sequences := _last_client_sequences.duplicate()
	var staged_copies: Dictionary = {}
	for runtime_id: int in _sorted_ids(staged_entities):
		if staged_entities[runtime_id]._requires_tick_transition(expected_tick):
			var transitioned: RefCounted = staged_entities[runtime_id]._duplicate_state()
			transitioned._begin_tick(expected_tick)
			staged_entities[runtime_id] = transitioned
			staged_copies[runtime_id] = true

	for interruption: RefCounted in sorted_interruptions:
		if not staged_entities.has(interruption.actor_id()):
			return _rejected_interruption(
				expected_tick,
				"cast.unknown_actor",
				interruption,
				"Cast interruption actor %d does not exist." % interruption.actor_id()
			)
		if not _ability_loadouts.has(interruption.actor_id()):
			return _rejected_interruption(
				expected_tick,
				"cast.actor_has_no_loadout",
				interruption,
				"Cast interruption actor %d has no ability loadout." % interruption.actor_id()
			)
		var interrupted_entity: RefCounted = staged_entities[interruption.actor_id()]
		if not staged_copies.has(interruption.actor_id()):
			interrupted_entity = interrupted_entity._duplicate_state()
			staged_entities[interruption.actor_id()] = interrupted_entity
			staged_copies[interruption.actor_id()] = true
		interrupted_entity._apply_interruption(
			interruption.reason_id(),
			_ability_loadouts[interruption.actor_id()]
		)

	for command: RefCounted in sorted_commands:
		if command.tick() < expected_tick:
			return _rejected(
				expected_tick,
				"command.late_tick",
				command,
				"Command tick %d precedes expected tick %d." % [command.tick(), expected_tick]
			)
		if command.tick() > expected_tick:
			return _rejected(
				expected_tick,
				"command.future_tick",
				command,
				"Command tick %d exceeds expected tick %d." % [command.tick(), expected_tick]
			)
		if not staged_entities.has(command.actor_id()):
			return _rejected(
				expected_tick,
				"command.unknown_actor",
				command,
				"Command actor %d does not exist." % command.actor_id()
			)
		var entity: RefCounted = staged_entities[command.actor_id()]
		if not entity.is_player_controlled():
			return _rejected(
				expected_tick,
				"command.actor_not_player",
				command,
				"Command actor %d is not player controlled." % command.actor_id()
			)
		var last_sequence: int = staged_sequences.get(command.actor_id(), 0)
		if command.client_sequence() == last_sequence:
			return _rejected(
				expected_tick,
				"command.duplicate_sequence",
				command,
				"Command sequence %d duplicates the actor's last accepted sequence."
				% command.client_sequence()
			)
		if command.client_sequence() < last_sequence:
			return _rejected(
				expected_tick,
				"command.non_monotonic_sequence",
				command,
				"Command sequence %d precedes the actor's last accepted sequence %d."
				% [command.client_sequence(), last_sequence]
			)
		if not staged_copies.has(command.actor_id()):
			entity = entity._duplicate_state()
			staged_entities[command.actor_id()] = entity
			staged_copies[command.actor_id()] = true
		var transition_error: String
		if _ability_loadouts.has(command.actor_id()):
			transition_error = entity._apply_command(
				command,
				expected_tick,
				_ability_loadouts[command.actor_id()]
			)
		else:
			transition_error = entity._apply_command(command)
		if not transition_error.is_empty():
			return _rejected(
				expected_tick,
				"command.impossible_sequence",
				command,
				transition_error
			)
		staged_sequences[command.actor_id()] = command.client_sequence()

	if _movement_environment != null:
		for runtime_id: int in _sorted_ids(staged_entities):
			var moving_entity: RefCounted = staged_entities[runtime_id]
			if (
				not moving_entity.is_player_controlled()
				or not moving_entity.is_alive()
				or moving_entity.movement_input().is_zero_approx()
			):
				continue
			var movement_result: Dictionary = _movement_environment.resolve_position(
				moving_entity.position(),
				moving_entity.movement_input(),
				FIXED_DELTA_SECONDS
			)
			var movement_error: String = movement_result.get("error", "")
			if not movement_error.is_empty():
				return _rejected_movement(expected_tick, runtime_id, movement_error)
			if not staged_copies.has(runtime_id):
				moving_entity = moving_entity._duplicate_state()
				staged_entities[runtime_id] = moving_entity
				staged_copies[runtime_id] = true
			var position_error: String = moving_entity._apply_position(movement_result["position"])
			if not position_error.is_empty():
				return _rejected_movement(expected_tick, runtime_id, position_error)

	for damage_result: RefCounted in damage_results:
		if not staged_entities.has(damage_result.target_entity_id()):
			return _rejected_damage(
				expected_tick,
				"damage.unknown_target",
				damage_result,
				"Damage target %d does not exist." % damage_result.target_entity_id()
			)
		var target: RefCounted = staged_entities[damage_result.target_entity_id()]
		if not staged_copies.has(damage_result.target_entity_id()):
			target = target._duplicate_state()
			staged_entities[damage_result.target_entity_id()] = target
			staged_copies[damage_result.target_entity_id()] = true
		var damage_error: String = target._apply_damage_result(damage_result)
		if not damage_error.is_empty():
			return _rejected_damage(
				expected_tick,
				"damage.invalid_commit",
				damage_result,
				damage_error
			)

	_tick = expected_tick
	_entities = staged_entities
	_last_client_sequences = staged_sequences
	_state_hash = ""
	return _result(_tick, true, sorted_commands.size(), [])


func presentation_snapshot() -> RefCounted:
	if not _is_configured:
		return null
	var entity_snapshots: Array = []
	for runtime_id: int in _sorted_entity_ids():
		var value := EntitySnapshot.new()
		value._publish(_entities[runtime_id], _tick)
		entity_snapshots.append(value)
	var result := Snapshot.new()
	result._publish(_tick, state_hash(), entity_snapshots)
	return result


func _compute_state_hash() -> String:
	var entity_values: Array = []
	for runtime_id: int in _sorted_entity_ids():
		entity_values.append(_entities[runtime_id]._canonical_values())
	var sequence_values: Array = []
	var sequence_ids: Array = _last_client_sequences.keys()
	sequence_ids.sort()
	for runtime_id: int in sequence_ids:
		sequence_values.append([runtime_id, _last_client_sequences[runtime_id]])
	var canonical: Array
	if not _ability_loadouts.is_empty():
		var loadout_values: Array = []
		for actor_id: int in _sorted_ids(_ability_loadouts):
			loadout_values.append([actor_id, _ability_loadouts[actor_id].canonical_values()])
		canonical = [
			CAST_STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			_movement_environment.canonical_values() if _movement_environment != null else [],
			loadout_values,
			entity_values,
			sequence_values,
		]
	elif _movement_environment == null:
		canonical = [
			STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			entity_values,
			sequence_values,
		]
	else:
		canonical = [
			MOVEMENT_STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			_movement_environment.canonical_values(),
			entity_values,
			sequence_values,
		]
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	assert(start_error == OK, "SHA-256 hashing must be available.")
	var update_error := context.update(JSON.stringify(canonical).to_utf8_buffer())
	assert(update_error == OK, "Canonical state hashing must accept UTF-8 input.")
	return context.finish().hex_encode()


func _sorted_entity_ids() -> Array:
	return _sorted_ids(_entities)


static func _sorted_ids(values: Dictionary) -> Array:
	var result: Array = values.keys()
	result.sort()
	return result


static func _command_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.actor_id() != right.actor_id():
		return left.actor_id() < right.actor_id()
	if left.client_sequence() != right.client_sequence():
		return left.client_sequence() < right.client_sequence()
	return left.command_type() < right.command_type()


static func _interruption_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.actor_id() != right.actor_id():
		return left.actor_id() < right.actor_id()
	return left.reason_id() < right.reason_id()


func _rejected(
	tick_value: int,
	code: String,
	command: Variant,
	message: String
) -> RefCounted:
	var actor_id := 0
	var client_sequence := 0
	if command is PlayerCommandContract:
		actor_id = command.actor_id()
		client_sequence = command.client_sequence()
	return _result(
		tick_value,
		false,
		0,
		[{
			"code": code,
			"tick": tick_value,
			"actor_id": actor_id,
			"client_sequence": client_sequence,
			"message": message,
		}]
	)


func _rejected_damage(
	tick_value: int,
	code: String,
	damage_result: Variant,
	message: String
) -> RefCounted:
	var source_entity_id := 0
	var target_entity_id := 0
	var origin_event_id := 0
	if damage_result is DamageResultContract:
		source_entity_id = damage_result.source_entity_id()
		target_entity_id = damage_result.target_entity_id()
		origin_event_id = damage_result.origin_event_id()
	return _result(
		tick_value,
		false,
		0,
		[{
			"code": code,
			"tick": tick_value,
			"source_entity_id": source_entity_id,
			"target_entity_id": target_entity_id,
			"origin_event_id": origin_event_id,
			"message": message,
		}]
	)


func _rejected_movement(tick_value: int, actor_id: int, message: String) -> RefCounted:
	return _result(
		tick_value,
		false,
		0,
		[{
			"code": "movement.invalid_state",
			"tick": tick_value,
			"actor_id": actor_id,
			"client_sequence": _last_client_sequences.get(actor_id, 0),
			"message": message,
		}]
	)


func _rejected_interruption(
	tick_value: int,
	code: String,
	interruption: Variant,
	message: String
) -> RefCounted:
	var actor_id := 0
	var reason_id := ""
	if interruption is CastInterruptionContract:
		actor_id = interruption.actor_id()
		reason_id = interruption.reason_id()
	return _result(
		tick_value,
		false,
		0,
		[{
			"code": code,
			"tick": tick_value,
			"actor_id": actor_id,
			"reason_id": reason_id,
			"message": message,
		}]
	)


static func _result(
	tick_value: int,
	is_success: bool,
	accepted_count: int,
	diagnostics: Array
) -> RefCounted:
	var result := CommandResult.new()
	result._configure(tick_value, is_success, accepted_count, diagnostics)
	return result
