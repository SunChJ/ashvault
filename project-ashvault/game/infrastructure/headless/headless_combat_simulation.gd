class_name HeadlessCombatSimulation
extends RefCounted

const AbilityDamageComponent = preload(
	"res://game/simulation/abilities/ability_damage_component.gd"
)
const AbilityDefinition = preload(
	"res://game/simulation/abilities/ability_definition.gd"
)
const AbilityEffectDefinition = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const AbilityExecutionContext = preload(
	"res://game/simulation/abilities/ability_execution_context.gd"
)
const AbilityExecutor = preload(
	"res://game/simulation/abilities/ability_executor.gd"
)
const CombatEventEmission = preload(
	"res://game/simulation/events/combat_event_emission.gd"
)
const CombatEventQueue = preload(
	"res://game/simulation/events/combat_event_queue.gd"
)
const CombatEventRequest = preload(
	"res://game/simulation/events/combat_event_request.gd"
)
const DamageModifier = preload(
	"res://game/simulation/combat/damage_modifier.gd"
)
const DamageContext = preload(
	"res://game/simulation/combat/damage_context.gd"
)
const EntityState = preload(
	"res://game/simulation/entities/entity_state.gd"
)
const EntityWorld = preload(
	"res://game/simulation/entities/entity_world.gd"
)
const PlayerCommand = preload(
	"res://game/simulation/commands/player_command.gd"
)
const RngStreams = preload(
	"res://game/simulation/random/rng_streams.gd"
)
const StableId = preload("res://game/content/stable_id.gd")
const StatDefinition = preload(
	"res://game/simulation/stats/stat_definition.gd"
)
const StatRegistry = preload(
	"res://game/simulation/stats/stat_registry.gd"
)
const StatResolver = preload(
	"res://game/simulation/stats/stat_resolver.gd"
)
const VersionInfo = preload(
	"res://game/infrastructure/version_info.gd"
)

const INPUT_SCHEMA_VERSION := 1
const STATE_HASH_SCHEMA_VERSION := 1
const BUILD_FIELDS := ["schema_version", "build_id", "actor", "ability", "mitigation"]
const ENCOUNTER_FIELDS := ["schema_version", "encounter_id", "target", "attack", "mitigation"]
const ENTITY_FIELDS := [
	"runtime_id", "definition_id", "position", "health", "max_health",
	"resource", "max_resource",
]
const PLAYER_ABILITY_FIELDS := [
	"slot", "ability_id", "rank", "damage_type_id", "base_damage", "power",
	"power_coefficient", "critical_chance", "critical_multiplier",
]
const ENEMY_ATTACK_FIELDS := [
	"ability_id", "damage_type_id", "base_damage", "power",
	"power_coefficient", "critical_chance", "critical_multiplier", "interval_ticks",
]
const MITIGATION_FIELDS := ["defense", "resistance"]
const REPLAY_FIELDS := ["schema_version", "batches"]
const BATCH_FIELDS := ["tick", "commands"]

const POWER_STAT_ID := "stat.offense.power"
const CRITICAL_CHANCE_STAT_ID := "stat.critical.chance"
const CRITICAL_MULTIPLIER_STAT_ID := "stat.critical.multiplier"

var _build: Dictionary = {}
var _encounter: Dictionary = {}
var _replay: Dictionary = {}
var _root_seed := 0
var _simulation_version := 0
var _content_version := 0
var _duration_ticks := 0
var _commands_by_tick: Dictionary = {}
var _command_count := 0
var _world: RefCounted = null
var _rng_streams: RefCounted = null
var _event_queue: RefCounted = null
var _player_package: Dictionary = {}
var _enemy_package: Dictionary = {}
var _player_mitigation: Array = []
var _target_mitigation: Array = []
var _player_id := 0
var _target_id := 0
var _player_slot := -1
var _enemy_interval_ticks := 0
var _next_origin_event_id := 1
var _commands_accepted := 0
var _damage_dealt := 0.0
var _damage_taken := 0.0
var _damage_mix: Dictionary = {}
var _hits := 0
var _critical_hits := 0
var _proc_events := 0
var _kills := 0
var _events_processed := 0
var _max_event_depth := 0
var _input_hashes := PackedStringArray()
var _is_configured := false


func configure(
	build: Dictionary,
	encounter: Dictionary,
	replay: Dictionary,
	root_seed: int,
	simulation_version: int,
	content_version: int,
	duration_ticks: int
) -> String:
	if _is_configured:
		return "Headless combat simulation is already configured."
	if simulation_version != VersionInfo.SIMULATION_VERSION:
		return "Requested simulation version %d does not match runtime version %d." % [
			simulation_version,
			VersionInfo.SIMULATION_VERSION,
		]
	if content_version != VersionInfo.CONTENT_VERSION:
		return "Requested content version %d does not match runtime version %d." % [
			content_version,
			VersionInfo.CONTENT_VERSION,
		]
	if duration_ticks <= 0:
		return "Headless simulation duration ticks must be positive."
	var build_error := _validate_build(build)
	if not build_error.is_empty():
		return build_error
	var encounter_error := _validate_encounter(encounter)
	if not encounter_error.is_empty():
		return encounter_error
	var replay_result := _parse_replay(replay, duration_ticks)
	if not replay_result["error"].is_empty():
		return replay_result["error"]

	var player_result := _entity_from_config(build["actor"], true)
	if not player_result["error"].is_empty():
		return player_result["error"]
	var target_result := _entity_from_config(encounter["target"], false)
	if not target_result["error"].is_empty():
		return target_result["error"]
	if player_result["entity"].runtime_id() == target_result["entity"].runtime_id():
		return "Build actor and encounter target runtime IDs must differ."
	var player_package := _combat_package(build["ability"], "player")
	if not player_package["error"].is_empty():
		return player_package["error"]
	var enemy_package := _combat_package(encounter["attack"], "enemy")
	if not enemy_package["error"].is_empty():
		return enemy_package["error"]

	var world := EntityWorld.new()
	var world_error: String = world.configure([
		target_result["entity"],
		player_result["entity"],
	])
	if not world_error.is_empty():
		return world_error
	var event_queue := CombatEventQueue.new()
	var queue_error: String = event_queue.configure()
	if not queue_error.is_empty():
		return queue_error
	var rng_streams := RngStreams.new()
	rng_streams.initialize(root_seed)

	_build = build.duplicate(true)
	_encounter = encounter.duplicate(true)
	_replay = replay.duplicate(true)
	_root_seed = root_seed
	_simulation_version = simulation_version
	_content_version = content_version
	_duration_ticks = duration_ticks
	_commands_by_tick = replay_result["commands_by_tick"]
	_command_count = replay_result["command_count"]
	_world = world
	_event_queue = event_queue
	_rng_streams = rng_streams
	_player_package = player_package
	_enemy_package = enemy_package
	_player_id = player_result["entity"].runtime_id()
	_target_id = target_result["entity"].runtime_id()
	_player_slot = int(build["ability"]["slot"])
	_enemy_interval_ticks = int(encounter["attack"]["interval_ticks"])
	_player_mitigation = _mitigation_modifiers(
		build["mitigation"],
		encounter["attack"]["damage_type_id"],
		"player"
	)
	_target_mitigation = _mitigation_modifiers(
		encounter["mitigation"],
		build["ability"]["damage_type_id"],
		"target"
	)
	_input_hashes = PackedStringArray([
		_hash_value(_build),
		_hash_value(_encounter),
		_hash_value(_replay),
	])
	_is_configured = true
	return ""


func tick() -> int:
	return _world.tick() if _world != null else -1


func entity_count() -> int:
	return _world.entity_count() if _world != null else 0


func is_complete() -> bool:
	return _is_configured and tick() >= _duration_ticks


func step() -> String:
	if not _is_configured:
		return "Headless combat simulation is not configured."
	if is_complete():
		return "Headless combat simulation is already complete."
	var next_tick := tick() + 1
	var commands: Array = _commands_by_tick.get(next_tick, []).duplicate()
	commands.sort_custom(_command_precedes)
	var rng_snapshot: Dictionary = _rng_streams.snapshot()
	var origin_event_before := _next_origin_event_id
	var damage_results: Array = []
	var event_requests: Array = []
	var attack_records: Array = []

	for command: RefCounted in commands:
		if (
			command.actor_id() == _player_id
			and command.command_type() == PlayerCommand.CAST_RELEASE
			and command.ability_slot() == _player_slot
			and _is_alive(_player_id)
			and _is_alive(_target_id)
		):
			var attack := _execute_attack(
				_player_package,
				_player_id,
				_target_id,
				_target_mitigation,
				next_tick
			)
			if not attack["error"].is_empty():
				_restore_rng(rng_snapshot, origin_event_before)
				return attack["error"]
			damage_results.append(attack["damage_result"])
			event_requests.append(attack["event_request"])
			attack_records.append(attack)
	if (
		next_tick % _enemy_interval_ticks == 0
		and _is_alive(_target_id)
		and _is_alive(_player_id)
	):
		var enemy_attack := _execute_attack(
			_enemy_package,
			_target_id,
			_player_id,
			_player_mitigation,
			next_tick
		)
		if not enemy_attack["error"].is_empty():
			_restore_rng(rng_snapshot, origin_event_before)
			return enemy_attack["error"]
		damage_results.append(enemy_attack["damage_result"])
		event_requests.append(enemy_attack["event_request"])
		attack_records.append(enemy_attack)

	var health_before := {
		_player_id: _world.entity_state(_player_id).health(),
		_target_id: _world.entity_state(_target_id).health(),
	}
	var commit: RefCounted = _world.advance_tick(commands, damage_results)
	if not commit.is_success():
		_restore_rng(rng_snapshot, origin_event_before)
		var diagnostic: Dictionary = commit.diagnostics()[0]
		return "%s: %s" % [diagnostic["code"], diagnostic["message"]]

	for request: RefCounted in event_requests:
		var event: RefCounted = _event_queue.enqueue_root(request)
		assert(event != null, "Configured simulator event requests must enqueue.")
	var event_result: RefCounted = _event_queue.process_tick(
		next_tick,
		Callable(self, "_handle_event")
	)
	assert(event_result.is_success(), "Simulator event expansion must remain valid and bounded.")
	assert(event_result.is_drained(), "Simulator events must drain within their source tick.")

	_commands_accepted += commit.accepted_count()
	_record_attacks(attack_records, health_before)
	for event: RefCounted in event_result.processed_events():
		_events_processed += 1
		_max_event_depth = maxi(_max_event_depth, event.depth())
		if event.depth() > 0:
			_proc_events += 1
	return ""


func state_hash() -> String:
	if not _is_configured:
		return ""
	var damage_mix_values: Array = []
	var damage_types: Array = _damage_mix.keys()
	damage_types.sort()
	for damage_type: String in damage_types:
		damage_mix_values.append([damage_type, _damage_mix[damage_type]])
	return _hash_value([
		STATE_HASH_SCHEMA_VERSION,
		_simulation_version,
		_content_version,
		str(_root_seed),
		_duration_ticks,
		_input_hashes,
		_world.state_hash(),
		_rng_streams.snapshot(),
		_event_queue.pending_count(),
		_next_origin_event_id,
		_commands_accepted,
		_damage_dealt,
		_damage_taken,
		damage_mix_values,
		_hits,
		_critical_hits,
		_proc_events,
		_kills,
		_events_processed,
		_max_event_depth,
	])


func deterministic_report() -> Dictionary:
	if not is_complete():
		return {}
	var seconds := float(_duration_ticks) / float(EntityWorld.FIXED_TICKS_PER_SECOND)
	var combat := {
		"damage_dealt": _damage_dealt,
		"damage_taken": _damage_taken,
		"dps": _damage_dealt / seconds,
		"damage_mix": _sorted_dictionary(_damage_mix),
		"hits": _hits,
		"critical_hits": _critical_hits,
		"critical_rate": _ratio(_critical_hits, _hits),
		"proc_events": _proc_events,
		"proc_rate": _ratio(_proc_events, _hits),
		"kills": _kills,
		"kills_per_second": float(_kills) / seconds,
		"events_processed": _events_processed,
		"max_event_depth": _max_event_depth,
	}
	var inputs := {
		"build_id": _build["build_id"],
		"encounter_id": _encounter["encounter_id"],
		"root_seed": str(_root_seed),
		"duration_ticks": _duration_ticks,
		"duration_seconds": seconds,
		"command_count": _command_count,
	}
	var replay := {
		"state_hash": state_hash(),
		"final_tick": tick(),
	}
	var ticks := {"commands_accepted": _commands_accepted}
	var report_hash := _hash_value({
		"inputs": inputs,
		"replay": replay,
		"combat": combat,
		"ticks": ticks,
	})
	replay["report_hash"] = report_hash
	return {
		"inputs": inputs,
		"replay": replay,
		"combat": combat,
		"ticks": ticks,
	}


func _execute_attack(
	package: Dictionary,
	source_entity_id: int,
	target_entity_id: int,
	target_modifiers: Array,
	tick_value: int
) -> Dictionary:
	var stat_result: RefCounted = StatResolver.resolve(
		package["registry"],
		[],
		PackedStringArray(),
		tick_value
	)
	if not stat_result.is_success():
		return {"error": "; ".join(stat_result.errors())}
	var critical_roll: float = _rng_streams.get_stream(RngStreams.COMBAT).next_float()
	var context := AbilityExecutionContext.new()
	var context_error: String = context.configure(
		package["rank"],
		tick_value,
		source_entity_id,
		target_entity_id,
		_next_origin_event_id,
		stat_result.snapshot(),
		critical_roll,
		PackedStringArray(),
		target_modifiers,
		_world.entity_state(target_entity_id).position(),
		_world.entity_state(source_entity_id).position().direction_to(
			_world.entity_state(target_entity_id).position()
		)
	)
	if not context_error.is_empty():
		return {"error": context_error}
	_next_origin_event_id += 1
	var execution: RefCounted = AbilityExecutor.execute(package["ability"], context)
	if not execution.is_success():
		return {"error": "; ".join(execution.errors())}
	var damage_result: RefCounted = null
	var event_request: RefCounted = null
	for output: RefCounted in execution.outputs():
		if output.damage_result() != null:
			damage_result = output.damage_result()
		if output.event_request() != null:
			event_request = output.event_request()
	if damage_result == null or event_request == null:
		return {"error": "Simulator ability must publish one damage result and one event request."}
	return {
		"error": "",
		"damage_result": damage_result,
		"event_request": event_request,
	}


func _record_attacks(records: Array, health_before: Dictionary) -> void:
	var remaining := health_before.duplicate()
	for record: Dictionary in records:
		var result: RefCounted = record["damage_result"]
		var target_id: int = result.target_entity_id()
		var before: int = remaining[target_id]
		var actual := mini(before, result.committed_amount())
		remaining[target_id] = before - actual
		_hits += 1
		if result.is_critical():
			_critical_hits += 1
		if result.source_entity_id() == _player_id:
			_damage_dealt += actual
			var scale: float = (
				float(actual) / float(result.total_damage())
				if result.total_damage() > 0.0
				else 0.0
			)
			for component: Dictionary in result.component_breakdown():
				var damage_type: String = component["damage_type_id"]
				_damage_mix[damage_type] = (
					_damage_mix.get(damage_type, 0.0) + component["final"] * scale
				)
		if target_id == _player_id:
			_damage_taken += actual
	if health_before[_target_id] > 0 and remaining[_target_id] == 0:
		_kills += 1


func _handle_event(event: RefCounted) -> Array:
	if event.event_type() != "event.hit":
		return []
	var request := CombatEventRequest.new()
	var request_error: String = request.configure(
		"event.damage",
		event.source_entity_id(),
		event.target_entity_id(),
		event.source_definition_id(),
		event.tags(),
		{}
	)
	assert(request_error.is_empty())
	var emission := CombatEventEmission.new()
	var emission_error: String = emission.configure(
		"trigger.simulator.damage_event",
		0,
		0,
		false,
		request
	)
	assert(emission_error.is_empty())
	return [emission]


func _restore_rng(snapshot: Dictionary, origin_event_id: int) -> void:
	var errors: PackedStringArray = _rng_streams.restore(snapshot)
	assert(errors.is_empty(), "Previously published RNG snapshots must restore.")
	_next_origin_event_id = origin_event_id


func _is_alive(runtime_id: int) -> bool:
	var entity: RefCounted = _world.entity_state(runtime_id)
	return entity != null and entity.is_alive()


static func _command_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.actor_id() != right.actor_id():
		return left.actor_id() < right.actor_id()
	return left.client_sequence() < right.client_sequence()


static func _ratio(numerator: int, denominator: int) -> float:
	return float(numerator) / float(denominator) if denominator > 0 else 0.0


static func _sorted_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = value.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = value[key]
	return result


static func _hash_value(value: Variant) -> String:
	var context := HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(JSON.stringify(_canonicalize(value)).to_utf8_buffer()) == OK)
	return context.finish().hex_encode()


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Array = []
		var keys: Array = value.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
		for key: Variant in keys:
			result.append([str(key), _canonicalize(value[key])])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonicalize(item))
		return result
	if value is PackedStringArray:
		return Array(value)
	return value


static func _validate_build(value: Dictionary) -> String:
	var error := _validate_exact_fields(value, BUILD_FIELDS, "Build fixture")
	if not error.is_empty():
		return error
	if value["schema_version"] != INPUT_SCHEMA_VERSION:
		return "Build fixture schema_version must equal %d." % INPUT_SCHEMA_VERSION
	if not value["build_id"] is String or not StableId.is_valid(value["build_id"]):
		return "Build fixture build_id must be a stable ID."
	error = _validate_entity(value["actor"], "Build actor")
	if not error.is_empty():
		return error
	error = _validate_ability(value["ability"], true, "Build ability")
	if not error.is_empty():
		return error
	return _validate_mitigation(value["mitigation"], "Build mitigation")


static func _validate_encounter(value: Dictionary) -> String:
	var error := _validate_exact_fields(value, ENCOUNTER_FIELDS, "Encounter fixture")
	if not error.is_empty():
		return error
	if value["schema_version"] != INPUT_SCHEMA_VERSION:
		return "Encounter fixture schema_version must equal %d." % INPUT_SCHEMA_VERSION
	if not value["encounter_id"] is String or not StableId.is_valid(value["encounter_id"]):
		return "Encounter fixture encounter_id must be a stable ID."
	error = _validate_entity(value["target"], "Encounter target")
	if not error.is_empty():
		return error
	error = _validate_ability(value["attack"], false, "Encounter attack")
	if not error.is_empty():
		return error
	return _validate_mitigation(value["mitigation"], "Encounter mitigation")


static func _validate_entity(value: Variant, label: String) -> String:
	if not value is Dictionary:
		return "%s must be an object." % label
	var error := _validate_exact_fields(value, ENTITY_FIELDS, label)
	if not error.is_empty():
		return error
	for field in ["runtime_id", "health", "max_health"]:
		error = _integer_error(value[field], "%s %s" % [label, field])
		if not error.is_empty():
			return error
	for field in ["resource", "max_resource"]:
		error = _number_error(value[field], "%s %s" % [label, field])
		if not error.is_empty():
			return error
	if not value["definition_id"] is String:
		return "%s definition_id must be a String." % label
	return _vector_error(value["position"], "%s position" % label)


static func _validate_ability(value: Variant, is_player: bool, label: String) -> String:
	if not value is Dictionary:
		return "%s must be an object." % label
	var fields := PLAYER_ABILITY_FIELDS if is_player else ENEMY_ATTACK_FIELDS
	var error := _validate_exact_fields(value, fields, label)
	if not error.is_empty():
		return error
	for field in ["ability_id", "damage_type_id"]:
		if not value[field] is String:
			return "%s %s must be a String." % [label, field]
	for field in [
		"base_damage", "power", "power_coefficient", "critical_chance",
		"critical_multiplier",
	]:
		error = _number_error(value[field], "%s %s" % [label, field])
		if not error.is_empty():
			return error
	if is_player:
		for field in ["slot", "rank"]:
			error = _integer_error(value[field], "%s %s" % [label, field])
			if not error.is_empty():
				return error
	else:
		error = _integer_error(value["interval_ticks"], "%s interval_ticks" % label)
		if not error.is_empty():
			return error
	if value["base_damage"] < 0.0 or value["power"] < 0.0 or value["power_coefficient"] < 0.0:
		return "%s damage and scaling values must be non-negative." % label
	if (
		value["critical_chance"] < 0.0
		or value["critical_chance"] > DamageContext.MAX_CRITICAL_CHANCE
	):
		return "%s critical_chance must be between zero and %s." % [
			label,
			DamageContext.MAX_CRITICAL_CHANCE,
		]
	if value["critical_multiplier"] < 1.0:
		return "%s critical_multiplier must be at least one." % label
	if is_player and (value["slot"] < 0 or value["rank"] < 1):
		return "%s slot must be non-negative and rank positive." % label
	if not is_player and value["interval_ticks"] < 1:
		return "%s interval_ticks must be positive." % label
	return ""


static func _validate_mitigation(value: Variant, label: String) -> String:
	if not value is Dictionary:
		return "%s must be an object." % label
	var error := _validate_exact_fields(value, MITIGATION_FIELDS, label)
	if not error.is_empty():
		return error
	for field in MITIGATION_FIELDS:
		error = _number_error(value[field], "%s %s" % [label, field])
		if not error.is_empty():
			return error
	if value["defense"] < 0.0:
		return "%s defense must be non-negative." % label
	return ""


static func _parse_replay(value: Dictionary, duration_ticks: int) -> Dictionary:
	var error := _validate_exact_fields(value, REPLAY_FIELDS, "Replay fixture")
	if not error.is_empty():
		return {"error": error}
	if value["schema_version"] != INPUT_SCHEMA_VERSION:
		return {"error": "Replay fixture schema_version must equal %d." % INPUT_SCHEMA_VERSION}
	if not value["batches"] is Array:
		return {"error": "Replay fixture batches must be an Array."}
	var commands_by_tick: Dictionary = {}
	var command_count := 0
	for index in value["batches"].size():
		var batch: Variant = value["batches"][index]
		if not batch is Dictionary:
			return {"error": "Replay batch %d must be an object." % index}
		error = _validate_exact_fields(batch, BATCH_FIELDS, "Replay batch %d" % index)
		if not error.is_empty():
			return {"error": error}
		error = _integer_error(batch["tick"], "Replay batch %d tick" % index)
		if not error.is_empty():
			return {"error": error}
		var tick_value := int(batch["tick"])
		if tick_value <= 0 or tick_value > duration_ticks:
			return {"error": "Replay batch tick %d is outside the simulation duration." % tick_value}
		if commands_by_tick.has(tick_value):
			return {"error": "Replay fixture repeats batch tick %d." % tick_value}
		if not batch["commands"] is Array:
			return {"error": "Replay batch %d commands must be an Array." % index}
		var commands: Array = []
		for command_index in batch["commands"].size():
			var command := PlayerCommand.new()
			var command_error: String = command.configure_from_dictionary(
				batch["commands"][command_index]
			)
			if not command_error.is_empty():
				return {"error": "Replay command %d:%d: %s" % [index, command_index, command_error]}
			if command.tick() != tick_value:
				return {"error": "Replay command tick must match its batch tick %d." % tick_value}
			commands.append(command)
			command_count += 1
		commands_by_tick[tick_value] = commands
	return {
		"error": "",
		"commands_by_tick": commands_by_tick,
		"command_count": command_count,
	}


static func _entity_from_config(value: Dictionary, player_controlled: bool) -> Dictionary:
	var position: Array = value["position"]
	var entity := EntityState.new()
	var error: String = entity.configure(
		int(value["runtime_id"]),
		value["definition_id"],
		player_controlled,
		Vector2(float(position[0]), float(position[1])),
		int(value["health"]),
		int(value["max_health"]),
		float(value["resource"]),
		float(value["max_resource"])
	)
	return {"entity": entity, "error": error}


static func _combat_package(value: Dictionary, role: String) -> Dictionary:
	var definitions: Array = []
	for fields in [
		[POWER_STAT_ID, float(value["power"])],
		[CRITICAL_CHANCE_STAT_ID, float(value["critical_chance"])],
		[CRITICAL_MULTIPLIER_STAT_ID, float(value["critical_multiplier"])],
	]:
		var definition := StatDefinition.new()
		var definition_error: String = definition.configure(fields[0], fields[1])
		if not definition_error.is_empty():
			return {"error": definition_error}
		definitions.append(definition)
	var registry := StatRegistry.new()
	var registry_errors: PackedStringArray = registry.load_definitions(definitions)
	if not registry_errors.is_empty():
		return {"error": "; ".join(registry_errors)}

	var component := AbilityDamageComponent.new()
	var component_error: String = component.configure(
		value["damage_type_id"],
		float(value["base_damage"]),
		POWER_STAT_ID,
		float(value["power_coefficient"]),
		"source.simulator.%s_base" % role
	)
	if not component_error.is_empty():
		return {"error": component_error}
	var damage_effect := AbilityEffectDefinition.new()
	var damage_effect_id := "effect.simulator.%s_damage" % role
	var damage_error: String = damage_effect.configure_damage(
		damage_effect_id,
		PackedStringArray([value["damage_type_id"]]),
		PackedStringArray(),
		[component],
		[],
		CRITICAL_CHANCE_STAT_ID,
		CRITICAL_MULTIPLIER_STAT_ID
	)
	if not damage_error.is_empty():
		return {"error": damage_error}
	var event_effect := AbilityEffectDefinition.new()
	var event_error: String = event_effect.configure_event(
		"effect.simulator.%s_hit" % role,
		PackedStringArray([value["damage_type_id"]]),
		PackedStringArray([damage_effect_id]),
		"event.hit",
		{}
	)
	if not event_error.is_empty():
		return {"error": event_error}
	var ability := AbilityDefinition.new()
	var ability_error: String = ability.configure_ability(
		value["ability_id"],
		["ability.simulator"],
		[],
		"",
		0.0,
		0,
		0,
		0,
		AbilityDefinition.Targeting.ENTITY,
		AbilityDefinition.Delivery.INSTANT,
		[damage_effect, event_effect],
		[]
	)
	if not ability_error.is_empty():
		return {"error": ability_error}
	return {
		"error": "",
		"ability": ability,
		"registry": registry,
		"rank": int(value.get("rank", 1)),
	}


static func _mitigation_modifiers(
	value: Dictionary,
	damage_type_id: String,
	role: String
) -> Array:
	var result: Array = []
	if value["defense"] > 0.0:
		var defense := DamageModifier.new()
		var defense_error: String = defense.configure(
			damage_type_id,
			DamageModifier.Operation.DEFENSE,
			float(value["defense"]),
			"source.simulator.%s_defense" % role
		)
		assert(defense_error.is_empty())
		result.append(defense)
	if value["resistance"] != 0.0:
		var resistance := DamageModifier.new()
		var resistance_error: String = resistance.configure(
			damage_type_id,
			DamageModifier.Operation.RESISTANCE,
			float(value["resistance"]),
			"source.simulator.%s_resistance" % role
		)
		assert(resistance_error.is_empty())
		result.append(resistance)
	return result


static func _validate_exact_fields(
	value: Dictionary,
	expected: Array,
	label: String
) -> String:
	for field: String in expected:
		if not value.has(field):
			return "%s is missing field '%s'." % [label, field]
	for field: Variant in value:
		if not expected.has(str(field)):
			return "%s has unexpected field '%s'." % [label, field]
	return ""


static func _number_error(value: Variant, label: String) -> String:
	if (not value is int and not value is float) or not is_finite(float(value)):
		return "%s must be a finite number." % label
	return ""


static func _integer_error(value: Variant, label: String) -> String:
	var error := _number_error(value, label)
	if not error.is_empty():
		return error
	if float(value) != floor(float(value)):
		return "%s must be an integer." % label
	return ""


static func _vector_error(value: Variant, label: String) -> String:
	if not value is Array or value.size() != 2:
		return "%s must be a two-number Array." % label
	for component: Variant in value:
		var error := _number_error(component, label)
		if not error.is_empty():
			return error
	return ""
