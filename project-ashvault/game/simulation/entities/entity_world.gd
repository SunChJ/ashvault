class_name EntityWorld
extends RefCounted

const PlayerCommandContract = preload("res://game/simulation/commands/player_command.gd")
const CommandResult = preload("res://game/simulation/commands/command_batch_result.gd")
const EntityStateContract = preload("res://game/simulation/entities/entity_state.gd")
const EntitySnapshot = preload("res://game/simulation/snapshots/presentation_entity_snapshot.gd")
const Snapshot = preload("res://game/simulation/snapshots/presentation_snapshot.gd")

const FIXED_TICKS_PER_SECOND := 60
const FIXED_DELTA_SECONDS := 1.0 / float(FIXED_TICKS_PER_SECOND)
const STATE_HASH_SCHEMA_VERSION := 1

var _tick := -1
var _entities: Dictionary = {}
var _last_client_sequences: Dictionary = {}
var _state_hash := ""
var _is_configured := false


func configure(initial_entities: Array, initial_tick: int = 0) -> String:
	if _is_configured:
		return "Entity world is already configured."
	if initial_tick < 0:
		return "Entity world initial tick must be non-negative."
	var staged_entities: Dictionary = {}
	for value: Variant in initial_entities:
		if not value is EntityStateContract or not value.is_configured():
			return "Every initial entity must be a configured EntityState."
		var runtime_id: int = value.runtime_id()
		if staged_entities.has(runtime_id):
			return "Duplicate runtime entity ID %d." % runtime_id
		staged_entities[runtime_id] = value._duplicate_state()
	_tick = initial_tick
	_entities = staged_entities
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


func advance_tick(commands: Array) -> RefCounted:
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
	sorted_commands.sort_custom(_command_precedes)

	var staged_entities := _entities.duplicate()
	var staged_sequences := _last_client_sequences.duplicate()
	var staged_copies: Dictionary = {}
	for runtime_id: int in _sorted_ids(staged_entities):
		if staged_entities[runtime_id]._requires_tick_transition():
			var transitioned: RefCounted = staged_entities[runtime_id]._duplicate_state()
			transitioned._begin_tick()
			staged_entities[runtime_id] = transitioned
			staged_copies[runtime_id] = true

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
		var transition_error: String = entity._apply_command(command)
		if not transition_error.is_empty():
			return _rejected(
				expected_tick,
				"command.impossible_sequence",
				command,
				transition_error
			)
		staged_sequences[command.actor_id()] = command.client_sequence()

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
		value._publish(_entities[runtime_id])
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
	var canonical := [
		STATE_HASH_SCHEMA_VERSION,
		FIXED_TICKS_PER_SECOND,
		_tick,
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


static func _result(
	tick_value: int,
	is_success: bool,
	accepted_count: int,
	diagnostics: Array
) -> RefCounted:
	var result := CommandResult.new()
	result._configure(tick_value, is_success, accepted_count, diagnostics)
	return result
