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
const EnemyAttackIntentContract = preload(
	"res://game/simulation/enemies/enemy_attack_intent.gd"
)
const EnemyDefinitionContract = preload(
	"res://game/simulation/enemies/enemy_definition.gd"
)
const EnemyRuntimeStateContract = preload(
	"res://game/simulation/enemies/enemy_runtime_state.gd"
)
const CombatEventRequestContract = preload(
	"res://game/simulation/events/combat_event_request.gd"
)
const MovementEnvironmentContract = preload("res://game/simulation/movement/movement_environment.gd")
const EntitySnapshot = preload("res://game/simulation/snapshots/presentation_entity_snapshot.gd")
const Snapshot = preload("res://game/simulation/snapshots/presentation_snapshot.gd")

const FIXED_TICKS_PER_SECOND := 60
const FIXED_DELTA_SECONDS := 1.0 / float(FIXED_TICKS_PER_SECOND)
const STATE_HASH_SCHEMA_VERSION := 1
const MOVEMENT_STATE_HASH_SCHEMA_VERSION := 2
const CAST_STATE_HASH_SCHEMA_VERSION := 3
const ENEMY_STATE_HASH_SCHEMA_VERSION := 4
const ENEMY_POSITION_QUANTUM := 0.001

var _tick := -1
var _entities: Dictionary = {}
var _last_client_sequences: Dictionary = {}
var _movement_environment: RefCounted = null
var _ability_loadouts: Dictionary = {}
var _enemy_definitions: Dictionary = {}
var _enemy_states: Dictionary = {}
var _state_hash := ""
var _is_configured := false


func configure(
	initial_entities: Array,
	initial_tick: int = 0,
	movement_environment: Variant = null,
	ability_loadouts: Dictionary = {},
	enemy_definitions: Dictionary = {}
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
	var staged_enemy_definitions: Dictionary = {}
	var staged_enemy_states: Dictionary = {}
	var enemy_ids: Array = enemy_definitions.keys()
	for enemy_id_value: Variant in enemy_ids:
		if not enemy_id_value is int or enemy_id_value <= 0:
			return "Enemy definition actor IDs must be positive integers."
	enemy_ids.sort()
	if not enemy_ids.is_empty() and movement_environment == null:
		return "Enemy runtime requires a configured movement environment."
	for enemy_id_value: Variant in enemy_ids:
		var enemy_id: int = enemy_id_value
		if not staged_entities.has(enemy_id):
			return "Enemy runtime actor %d does not exist." % enemy_id
		var enemy_entity: RefCounted = staged_entities[enemy_id]
		if enemy_entity.is_player_controlled():
			return "Enemy runtime actor %d must not be player controlled." % enemy_id
		var enemy_definition: Variant = enemy_definitions[enemy_id]
		if not enemy_definition is EnemyDefinitionContract or not enemy_definition.is_configured():
			return "Enemy runtime actor %d requires a configured EnemyDefinition." % enemy_id
		if enemy_definition.definition_id() != enemy_entity.definition_id():
			return "Enemy runtime actor %d definition does not match its entity." % enemy_id
		var enemy_placement_error: String = movement_environment.placement_error_for(
			enemy_entity.position(),
			enemy_definition.collision_radius()
		)
		if not enemy_placement_error.is_empty():
			return "Enemy %d has invalid movement placement: %s" % [
				enemy_id,
				enemy_placement_error,
			]
		staged_enemy_definitions[enemy_id] = enemy_definition
		var enemy_state := EnemyRuntimeStateContract.new()
		var enemy_state_error: String = enemy_state.configure(enemy_id)
		assert(enemy_state_error.is_empty(), "Valid enemy runtime state must configure.")
		staged_enemy_states[enemy_id] = enemy_state
	_tick = initial_tick
	_entities = staged_entities
	_movement_environment = (
		movement_environment._duplicate_value() if movement_environment != null else null
	)
	_ability_loadouts = staged_loadouts
	_enemy_definitions = staged_enemy_definitions
	_enemy_states = staged_enemy_states
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


func enemy_target_id(runtime_id: int) -> int:
	var value: Variant = _enemy_states.get(runtime_id)
	return value.target_id() if value != null else 0


func enemy_runtime_values() -> Array:
	var values: Array = []
	for runtime_id: int in _sorted_ids(_enemy_states):
		values.append(_enemy_states[runtime_id].canonical_values())
	return values


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
	var sorted_damage_results: Array = damage_results.duplicate()
	sorted_damage_results.sort_custom(_damage_precedes)
	var sorted_interruptions: Array = cast_interruptions.duplicate()
	sorted_interruptions.sort_custom(_interruption_precedes)

	var staged_entities := _entities.duplicate()
	var staged_sequences := _last_client_sequences.duplicate()
	var staged_enemy_states: Dictionary = {}
	for enemy_id: int in _sorted_ids(_enemy_states):
		staged_enemy_states[enemy_id] = _enemy_states[enemy_id]._duplicate_state()
	var staged_copies: Dictionary = {}
	var enemy_attack_intents: Array = []
	var combat_events: Array = []
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

	for damage_result: RefCounted in sorted_damage_results:
		if not staged_entities.has(damage_result.target_entity_id()):
			return _rejected_damage(
				expected_tick,
				"damage.unknown_target",
				damage_result,
				"Damage target %d does not exist." % damage_result.target_entity_id()
			)
		var target: RefCounted = staged_entities[damage_result.target_entity_id()]
		var was_alive: bool = target.is_alive()
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
		if was_alive and not target.is_alive():
			combat_events.append(_kill_event(damage_result))

	for enemy_id: int in _sorted_ids(staged_enemy_states):
		var enemy_entity: RefCounted = staged_entities[enemy_id]
		var enemy_state: RefCounted = staged_enemy_states[enemy_id]
		if not enemy_entity.is_alive():
			enemy_state._set_target_id(0)
			continue
		var enemy_definition: RefCounted = _enemy_definitions[enemy_id]
		var target_id := _retained_or_nearest_target(
			enemy_entity,
			enemy_state.target_id(),
			enemy_definition.acquisition_range(),
			staged_entities
		)
		enemy_state._set_target_id(target_id)
		if target_id == 0:
			continue
		var target_entity: RefCounted = staged_entities[target_id]
		var displacement: Vector2 = target_entity.position() - enemy_entity.position()
		var distance := displacement.length()
		if distance <= enemy_definition.attack_range():
			if expected_tick >= enemy_state.next_attack_tick():
				var intent := EnemyAttackIntentContract.new()
				var intent_error: String = intent.configure(
					expected_tick,
					enemy_id,
					target_id,
					enemy_definition.attack_id(),
					enemy_entity.position(),
					target_entity.position()
				)
				if not intent_error.is_empty():
					return _rejected_enemy(expected_tick, enemy_id, intent_error)
				enemy_attack_intents.append(intent)
				enemy_state._set_next_attack_tick(
					expected_tick + enemy_definition.attack_cooldown_ticks()
				)
			continue
		var allowed_distance := maxf(0.0, distance - enemy_definition.attack_range())
		var desired_distance := minf(
			enemy_definition.movement_speed_per_second() * FIXED_DELTA_SECONDS,
			allowed_distance
		)
		var movement_result: Dictionary = _movement_environment.resolve_position_for(
			enemy_entity.position(),
			displacement.normalized(),
			FIXED_DELTA_SECONDS,
			enemy_definition.collision_radius(),
			desired_distance / FIXED_DELTA_SECONDS
		)
		var movement_error: String = movement_result.get("error", "")
		if not movement_error.is_empty():
			return _rejected_enemy(expected_tick, enemy_id, movement_error)
		if not staged_copies.has(enemy_id):
			enemy_entity = enemy_entity._duplicate_state()
			staged_entities[enemy_id] = enemy_entity
			staged_copies[enemy_id] = true
		var next_position := _quantized_enemy_position(movement_result["position"])
		var placement_error: String = _movement_environment.placement_error_for(
			next_position,
			enemy_definition.collision_radius()
		)
		if not placement_error.is_empty():
			return _rejected_enemy(expected_tick, enemy_id, placement_error)
		var position_error: String = enemy_entity._apply_position(next_position)
		if not position_error.is_empty():
			return _rejected_enemy(expected_tick, enemy_id, position_error)

	_tick = expected_tick
	_entities = staged_entities
	_last_client_sequences = staged_sequences
	_enemy_states = staged_enemy_states
	_state_hash = ""
	return _result(
		_tick,
		true,
		sorted_commands.size(),
		[],
		enemy_attack_intents,
		combat_events
	)


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
	if not _enemy_definitions.is_empty():
		var enemy_definition_values: Array = []
		for actor_id: int in _sorted_ids(_enemy_definitions):
			enemy_definition_values.append([
				actor_id,
				_enemy_definitions[actor_id].canonical_values(),
			])
		var enemy_state_values: Array = []
		for actor_id: int in _sorted_ids(_enemy_states):
			enemy_state_values.append(_enemy_states[actor_id].canonical_values())
		var loadout_values: Array = []
		for actor_id: int in _sorted_ids(_ability_loadouts):
			loadout_values.append([actor_id, _ability_loadouts[actor_id].canonical_values()])
		canonical = [
			ENEMY_STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			_movement_environment.canonical_values(),
			loadout_values,
			enemy_definition_values,
			enemy_state_values,
			entity_values,
			sequence_values,
		]
	elif not _ability_loadouts.is_empty():
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


static func _retained_or_nearest_target(
	enemy: RefCounted,
	current_target_id: int,
	acquisition_range: float,
	entities: Dictionary
) -> int:
	var range_squared := acquisition_range * acquisition_range
	if _is_valid_enemy_target(enemy, current_target_id, range_squared, entities):
		return current_target_id
	var nearest_target_id := 0
	var nearest_distance_squared := INF
	for runtime_id: int in _sorted_ids(entities):
		if not _is_valid_enemy_target(enemy, runtime_id, range_squared, entities):
			continue
		var target: RefCounted = entities[runtime_id]
		var distance_squared: float = enemy.position().distance_squared_to(target.position())
		if distance_squared < nearest_distance_squared:
			nearest_target_id = runtime_id
			nearest_distance_squared = distance_squared
	return nearest_target_id


static func _is_valid_enemy_target(
	enemy: RefCounted,
	target_id: int,
	range_squared: float,
	entities: Dictionary
) -> bool:
	if target_id <= 0 or not entities.has(target_id):
		return false
	var target: RefCounted = entities[target_id]
	return (
		target.is_player_controlled()
		and target.is_alive()
		and enemy.position().distance_squared_to(target.position()) <= range_squared
	)


static func _kill_event(damage_result: RefCounted) -> RefCounted:
	var request := CombatEventRequestContract.new()
	var error: String = request.configure(
		"event.kill",
		damage_result.source_entity_id(),
		damage_result.target_entity_id(),
		damage_result.ability_id(),
		PackedStringArray(["event.kill"]),
		{
			"committed_damage": damage_result.committed_amount(),
			"origin_event_id": damage_result.origin_event_id(),
		}
	)
	assert(error.is_empty(), "Resolved damage must produce a valid kill event request.")
	return request


static func _quantized_enemy_position(value: Vector2) -> Vector2:
	return Vector2(
		snappedf(value.x, ENEMY_POSITION_QUANTUM),
		snappedf(value.y, ENEMY_POSITION_QUANTUM)
	)


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


static func _damage_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.target_entity_id() != right.target_entity_id():
		return left.target_entity_id() < right.target_entity_id()
	if left.origin_event_id() != right.origin_event_id():
		return left.origin_event_id() < right.origin_event_id()
	if left.source_entity_id() != right.source_entity_id():
		return left.source_entity_id() < right.source_entity_id()
	return left.ability_id() < right.ability_id()


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


func _rejected_enemy(tick_value: int, actor_id: int, message: String) -> RefCounted:
	return _result(
		tick_value,
		false,
		0,
		[{
			"code": "enemy.invalid_state",
			"tick": tick_value,
			"actor_id": actor_id,
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
	diagnostics: Array,
	enemy_attack_intents: Array = [],
	combat_events: Array = []
) -> RefCounted:
	var result := CommandResult.new()
	result._configure(
		tick_value,
		is_success,
		accepted_count,
		diagnostics,
		enemy_attack_intents,
		combat_events
	)
	return result
