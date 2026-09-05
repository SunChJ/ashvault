class_name StormweaverCombat
extends RefCounted

const Catalog = preload("res://game/simulation/abilities/stormweaver_catalog.gd")
const Ability = preload("res://game/simulation/abilities/ability_definition.gd")
const Effect = preload("res://game/simulation/abilities/ability_effect_definition.gd")
const Executor = preload("res://game/simulation/abilities/ability_executor.gd")
const Context = preload("res://game/simulation/abilities/ability_execution_context.gd")
const Entity = preload("res://game/simulation/entities/entity_state.gd")
const World = preload("res://game/simulation/entities/entity_world.gd")
const Command = preload("res://game/simulation/commands/player_command.gd")
const Movement = preload("res://game/simulation/movement/movement_environment.gd")
const Deliveries = preload("res://game/simulation/delivery/delivery_world.gd")
const DeliveryRequest = preload("res://game/simulation/delivery/delivery_request.gd")
const DeliveryTarget = preload("res://game/simulation/delivery/delivery_target.gd")
const Statuses = preload("res://game/simulation/statuses/status_world.gd")
const StatusTarget = preload("res://game/simulation/statuses/status_target.gd")
const Removal = preload("res://game/simulation/statuses/status_removal.gd")
const Application = preload("res://game/simulation/statuses/status_application.gd")
const Streams = preload("res://game/simulation/random/rng_streams.gd")
const Queue = preload("res://game/simulation/events/combat_event_queue.gd")
const Emission = preload("res://game/simulation/events/combat_event_emission.gd")
const EventRequest = preload("res://game/simulation/events/combat_event_request.gd")

const Snapshot = preload("res://game/simulation/stats/stat_snapshot.gd")
const DamageModifier = preload("res://game/simulation/combat/damage_modifier.gd")

const TOTEM_PLACEMENT_DISTANCE := 100.0

var _catalog: RefCounted
var _world: RefCounted
var _delivery: RefCounted
var _statuses: RefCounted
var _rng: RefCounted
var _environment: RefCounted
var _enemy_abilities: Dictionary = {}
var _enemy_definitions: Dictionary = {}
var _ids: Array = []
var _player_id := 0
var _next_request := 1
var _next_mutation := 1
var _next_origin := 1
var _next_event := 1
var _request_slots: Dictionary = {}
var _dash_direction := Vector2.ZERO
var _dash_distance_per_tick := 0.0
var _dash_end_tick := 0
var _last_report: Dictionary = {}
var _content_hash := ""
var _player_stats: RefCounted
var _player_mitigation: Array = []
var _player_tick_stats: RefCounted
var _tick_stats: RefCounted
var _configured := false


func configure(
	entities: Array,
	environment: Variant,
	catalog: Variant,
	seed_value: int = 1,
	enemy_definitions: Dictionary = {},
	enemy_abilities: Dictionary = {},
	player_stats: Variant = null,
	player_mitigation: Array = []
) -> String:
	if _configured:
		return "Stormweaver combat is already configured."
	if not catalog is Catalog or not catalog.is_configured():
		return "Combat requires a configured Stormweaver catalog."
	if not environment is Movement or not environment.is_configured():
		return "Combat requires a configured movement environment."
	if player_stats != null:
		if not player_stats is Snapshot or player_stats.tick() < 0:
			return "Player stats require a published StatSnapshot."
		for id: String in [Catalog.POWER, Catalog.CRIT, Catalog.CRIT_MULTIPLIER]:
			if not player_stats.has_stat(id) or not is_finite(player_stats.value(id)):
				return "Player stats require finite power and critical values."
		if player_stats.value(Catalog.POWER) < 0 or player_stats.value(Catalog.CRIT) < 0 or player_stats.value(Catalog.CRIT) > 0.95 or player_stats.value(Catalog.CRIT_MULTIPLIER) < 1:
			return "Player combat stats are outside their supported ranges."
	var mitigation_ids: Dictionary = {}
	for modifier: Variant in player_mitigation:
		if not modifier is DamageModifier or not modifier.is_configured() or mitigation_ids.has(modifier.identity_key()):
			return "Player mitigation requires distinct configured damage modifiers."
		mitigation_ids[modifier.identity_key()] = true
	var ids: Array = []
	var player_id := 0
	for entity: Variant in entities:
		if not entity is Entity or not entity.is_configured():
			return "Combat requires configured entities."
		ids.append(entity.runtime_id())
		if entity.is_player_controlled():
			if player_id != 0:
				return "Stormweaver slice supports exactly one player."
			player_id = entity.runtime_id()
	if player_id == 0:
		return "Combat requires one player."
	var world := World.new()
	var error: String = world.configure(entities, 0, environment, {player_id: catalog.loadout()}, enemy_definitions)
	if not error.is_empty():
		return error
	for id: int in enemy_definitions:
		var attack_id: String = enemy_definitions[id].attack_id()
		if not enemy_abilities.has(attack_id):
			return "Enemy attack '%s' has no definition." % attack_id
	for attack_id: Variant in enemy_abilities:
		if not attack_id is String:
			return "Enemy attack IDs must be Strings."
		var ability: Variant = enemy_abilities[attack_id]
		if not ability is Ability or not ability.is_configured() or ability.delivery() != Ability.Delivery.INSTANT or ability.targeting() != Ability.Targeting.ENTITY:
			return "Enemy attack '%s' requires an instant entity-targeted ability." % attack_id
		for effect: Resource in ability.effects_for_rank(1):
			if effect.kind() != Effect.Kind.DAMAGE:
				return "Ordinary enemy attacks support damage effects only."
		ability.freeze()
	_catalog = catalog
	_world = world
	_environment = environment
	_enemy_definitions = enemy_definitions.duplicate()
	_enemy_abilities = enemy_abilities.duplicate()
	_ids = ids
	_ids.sort()
	_player_id = player_id
	_delivery = Deliveries.new()
	Catalog._checked(_delivery.configure())
	_statuses = Statuses.new()
	var impacts: Array = enemy_abilities.values()
	for slot in Catalog.SKILLS.size():
		impacts.append(catalog.impact(slot))
	Catalog._checked(_statuses.configure(Catalog.statuses(Catalog.damage_types(impacts))))
	var attack_values: Array = []
	var attack_ids: Array = enemy_abilities.keys()
	attack_ids.sort()
	for attack_id: String in attack_ids:
		attack_values.append([attack_id, Catalog.ability_values(enemy_abilities[attack_id])])
	_content_hash = JSON.stringify([catalog.canonical_values(), attack_values, Catalog.default_stats().values()]).sha256_text()
	_player_stats = player_stats
	_player_mitigation = player_mitigation.duplicate()
	if player_stats != null or not player_mitigation.is_empty():
		var mitigation_values: Array = []
		for modifier: RefCounted in player_mitigation:
			mitigation_values.append(modifier.explanation_fields())
		_content_hash = JSON.stringify([_content_hash, player_stats.values() if player_stats != null else {}, mitigation_values]).sha256_text()
	_rng = Streams.new()
	_rng.initialize(seed_value)
	_configured = true
	return ""


func tick() -> int:
	return _world.tick() if _configured else -1


func entity_state(id: int) -> RefCounted:
	return _world.entity_state(id)


func presentation_snapshot() -> RefCounted:
	return _world.presentation_snapshot()


func status_stacks(id: int, status_id: String) -> int:
	return _statuses.stack_count(id, status_id)


func status_expiry(id: int, status_id: String) -> int:
	return _statuses.expiry_tick(id, status_id)


func report() -> Dictionary:
	return _last_report.duplicate(true)


func state_hash() -> String:
	if not _configured:
		return ""
	var requests: Array = []
	var request_ids: Array = _request_slots.keys()
	request_ids.sort()
	for id: int in request_ids:
		requests.append([id, _request_slots[id]])
	return JSON.stringify([
		1, _content_hash, _world.state_hash(), _delivery.state_hash(), _statuses.state_hash(),
		_rng.snapshot(), _next_request, _next_mutation, _next_origin, _next_event,
		requests, _dash_direction.x, _dash_direction.y, _dash_distance_per_tick, _dash_end_tick,
	]).sha256_text()


func advance_tick(commands: Array = [], interruptions: Array = []) -> String:
	if not _configured:
		return "Stormweaver combat is not configured."
	var staged := _duplicate_combat()
	var error: String = staged._step(commands, interruptions)
	if not error.is_empty():
		return error
	_world = staged._world
	_delivery = staged._delivery
	_statuses = staged._statuses
	_rng = staged._rng
	_next_request = staged._next_request
	_next_mutation = staged._next_mutation
	_next_origin = staged._next_origin
	_next_event = staged._next_event
	_request_slots = staged._request_slots
	_dash_direction = staged._dash_direction
	_dash_distance_per_tick = staged._dash_distance_per_tick
	_dash_end_tick = staged._dash_end_tick
	_last_report = staged._last_report
	return ""


func _step(commands: Array, interruptions: Array) -> String:
	var next_tick := tick() + 1
	_tick_stats = Catalog.default_stats(next_tick)
	_player_tick_stats = _tick_stats
	if _player_stats != null:
		_player_tick_stats = Snapshot.new()
		Catalog._checked(_player_tick_stats._configure(next_tick, _player_stats.values(), {}))
	var preview: RefCounted = _world._duplicate_world()
	var accepted: RefCounted = preview.advance_tick(commands, [], interruptions)
	if not accepted.is_success():
		return str(accepted.diagnostics())
	var actor: RefCounted = preview.entity_state(_player_id)
	var release_slot := -1
	for command: RefCounted in commands:
		if command.command_type() == Command.CAST_RELEASE:
			release_slot = command.ability_slot()
	# A canceled or interrupted dash cannot continue moving under a stale timer.
	if not actor.is_alive() or actor.cast_phase() == Entity.CAST_CANCELED:
		_dash_end_tick = 0
	if release_slot == Catalog.TEMPEST_DASH:
		for effect: Resource in _catalog.activation(release_slot).effects_for_rank(_catalog.rank_for(release_slot)):
			if effect.kind() == Effect.Kind.MOVEMENT:
				_dash_direction = actor.aim_direction()
				_dash_distance_per_tick = effect.distance() / float(effect.duration_ticks())
				_dash_end_tick = next_tick + effect.duration_ticks()
	var forced: Dictionary = {}
	if next_tick < _dash_end_tick:
		forced[_player_id] = _dash_direction * _dash_distance_per_tick
		preview = _world._duplicate_world()
		accepted = preview.advance_tick(commands, [], interruptions, forced)
		if not accepted.is_success():
			return str(accepted.diagnostics())
		actor = preview.entity_state(_player_id)

	var removals: Array = []
	if _dash_end_tick == 0 and _statuses.stack_count(_player_id, Catalog.INVULNERABLE) > 0:
		var removal := Removal.new()
		Catalog._checked(removal.configure(_next_mutation, _player_id, _player_id, Catalog.INVULNERABLE, Removal.Reason.FORCED))
		_next_mutation += 1
		removals.append(removal)
	var applications: Array = []
	var requests: Array = []
	var events: Array = []
	if release_slot >= 0:
		var activation: Resource = _catalog.activation(release_slot)
		var target_id := _player_id if release_slot == Catalog.TEMPEST_DASH else _nearest_target(preview, actor.position())
		# An empty chain cast still commits cost and cooldown, with no impact.
		if activation.targeting() != Ability.Targeting.ENTITY or target_id != 0:
			var position: Vector2 = actor.position()
			if activation.targeting() == Ability.Targeting.POINT:
				position += actor.aim_direction() * TOTEM_PLACEMENT_DISTANCE
				var placement: Dictionary = _environment.resolve_position_for(actor.position(), actor.aim_direction(), 1.0,
					_environment.actor_radius(), TOTEM_PLACEMENT_DISTANCE)
				position = placement.position
			var execution := _execute(activation, _catalog.rank_for(release_slot), _player_id,
				target_id, position, actor.aim_direction(), next_tick, null, false)
			if not execution.is_success():
				return str(execution.errors())
			_collect_outputs(execution, applications, [], events)
			var definition: Resource = _catalog.delivery(release_slot)
			if definition != null:
				var request := DeliveryRequest.new()
				var error: String = request.configure(_next_request, definition, _player_id, 1,
					position, actor.aim_direction(), target_id)
				if not error.is_empty():
					return error
				_request_slots[_next_request] = release_slot
				_next_request += 1
				requests.append(request)

	var status_targets := _status_targets(preview)
	var defensive_statuses: RefCounted = _statuses._duplicate_world()
	var defense_result: RefCounted = defensive_statuses.advance_tick(status_targets, applications, removals)
	if not defense_result.is_success():
		return str(defense_result.diagnostics())
	var delivery_result: RefCounted = _delivery.advance_tick(_delivery_targets(preview), requests)
	if not delivery_result.is_success():
		return str(delivery_result.diagnostics())
	var damages: Array = []
	var hit_records: Array = []
	for hit: RefCounted in delivery_result.hits():
		var slot: int = _request_slots[hit.request_id()]
		var execution := _execute(_catalog.impact(slot), 1, hit.source_entity_id(), hit.target_entity_id(),
			hit.impact_position(), Vector2.RIGHT, next_tick, defensive_statuses, true)
		if not execution.is_success():
			return str(execution.errors())
		_collect_outputs(execution, applications, damages, events)
		hit_records.append(hit.canonical_values())
	# EntityWorld commits player damage before enemies decide whether they can attack.
	var attack_preview: RefCounted = _world._duplicate_world()
	var attack_result: RefCounted = attack_preview.advance_tick(commands, damages, interruptions, forced)
	if not attack_result.is_success():
		return str(attack_result.diagnostics())
	for intent: RefCounted in attack_result.enemy_attack_intents():
		var execution := _execute(_enemy_abilities[intent.attack_id()], 1, intent.source_entity_id(),
			intent.target_entity_id(), intent.target_position(), intent.direction(), next_tick, defensive_statuses, true)
		if not execution.is_success():
			return str(execution.errors())
		_collect_outputs(execution, applications, damages, events)

	var commit: RefCounted = _world.advance_tick(commands, damages, interruptions, forced)
	if not commit.is_success():
		return str(commit.diagnostics())
	var status_result: RefCounted = _statuses.advance_tick(status_targets, applications, removals)
	if not status_result.is_success():
		return str(status_result.diagnostics())
	events.append_array(status_result.events())
	events.append_array(commit.combat_events())
	var queue := Queue.new()
	Catalog._checked(queue.configure(Queue.DEFAULT_MAX_DEPTH, Queue.DEFAULT_TICK_BUDGET, _next_event))
	for event: RefCounted in events:
		if queue.enqueue_root(event) == null:
			return "Combat event could not enter the bounded queue."
	var processed: RefCounted = queue.process_tick(next_tick, _handle_event)
	if not processed.is_success() or not processed.is_drained():
		return "Combat event budget exceeded."
	_next_event += processed.processed_events().size()
	var event_records: Array = []
	for event: RefCounted in processed.processed_events():
		event_records.append([event.event_type(), event.source_entity_id(), event.target_entity_id()])
	var active_requests: Dictionary = {}
	for value: Array in _delivery.active_values():
		active_requests[value[1]] = _request_slots[value[1]]
	_request_slots = active_requests
	var damage_records: Array = []
	for damage: RefCounted in damages:
		damage_records.append([damage.source_entity_id(), damage.target_entity_id(),
			damage.committed_amount(), damage.is_critical()])
	_last_report = {"tick": next_tick, "released_slot": release_slot, "hits": hit_records,
		"damage": damage_records, "statuses": _statuses.active_values(), "events": event_records,
		"active_deliveries": _delivery.active_count(), "deliveries": _delivery.active_values(),
		"state_hash": state_hash()}
	return ""


func _execute(ability: Resource, rank_value: int, source: int, target: int, position: Vector2,
	direction: Vector2, tick_value: int, statuses: RefCounted, roll_critical: bool) -> RefCounted:
	var context := Context.new()
	var roll: float = _rng.get_stream(Streams.COMBAT).next_float() if roll_critical else 1.0
	var conditions := PackedStringArray()
	var modifiers: Array = []
	if statuses != null:
		conditions = statuses.active_condition_ids(target)
		modifiers = statuses.damage_modifiers_for(target)
	if target == _player_id:
		modifiers.append_array(_player_mitigation)
	var error: String = context.configure(rank_value, tick_value, source, target, _next_origin,
		_player_tick_stats if source == _player_id else _tick_stats, roll, conditions, modifiers, position, direction)
	_next_origin += 1
	if not error.is_empty():
		return Executor._result([], error)
	return Executor.execute(ability, context)


func _collect_outputs(execution: RefCounted, applications: Array, damages: Array, events: Array) -> void:
	for output: RefCounted in execution.outputs():
		if output.damage_result() != null:
			var damage: RefCounted = output.damage_result()
			damages.append(damage)
			var hit_event := EventRequest.new()
			Catalog._checked(hit_event.configure("event.hit", damage.source_entity_id(), damage.target_entity_id(),
				damage.ability_id(), [], {"critical": damage.is_critical(), "amount": damage.committed_amount()}))
			events.append(hit_event)
		if output.event_request() != null:
			events.append(output.event_request())
		var command: RefCounted = output.command()
		if command != null and command.effect().kind() == Effect.Kind.STATUS:
			var effect: Resource = command.effect()
			var application := Application.new()
			Catalog._checked(application.configure(_next_mutation, effect.status_definition_id(),
				command.source_entity_id(), command.target_entity_id(), effect.duration_ticks(), effect.stacks()))
			_next_mutation += 1
			applications.append(application)


func _nearest_target(world: RefCounted, origin: Vector2) -> int:
	var nearest := 0
	var distance := INF
	for id: int in _ids:
		var entity: RefCounted = world.entity_state(id)
		if entity.is_player_controlled() or not entity.is_alive():
			continue
		var candidate: float = origin.distance_squared_to(entity.position())
		if candidate < distance:
			distance = candidate
			nearest = id
	return nearest


func _status_targets(world: RefCounted) -> Array:
	var targets: Array = []
	for id: int in _ids:
		var target := StatusTarget.new()
		Catalog._checked(target.configure(id, world.entity_state(id).is_alive()))
		targets.append(target)
	return targets


func _delivery_targets(world: RefCounted) -> Array:
	var targets: Array = []
	for id: int in _ids:
		var entity: RefCounted = world.entity_state(id)
		var target := DeliveryTarget.new()
		var radius: float = _environment.actor_radius()
		if _enemy_definitions.has(id):
			radius = _enemy_definitions[id].collision_radius()
		Catalog._checked(target.configure(id, 1 if entity.is_player_controlled() else 2,
			entity.position(), radius, entity.is_alive()))
		targets.append(target)
	return targets


func _duplicate_combat() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._catalog = _catalog
	result._player_stats = _player_stats
	result._player_mitigation = _player_mitigation
	result._environment = _environment
	result._enemy_definitions = _enemy_definitions
	result._enemy_abilities = _enemy_abilities
	result._ids = _ids
	result._player_id = _player_id
	result._world = _world._duplicate_world()
	result._delivery = _delivery._duplicate_world()
	result._statuses = _statuses._duplicate_world()
	result._rng = Streams.new()
	var errors: PackedStringArray = result._rng.restore(_rng.snapshot())
	assert(errors.is_empty())
	result._next_request = _next_request
	result._next_mutation = _next_mutation
	result._next_origin = _next_origin
	result._next_event = _next_event
	result._request_slots = _request_slots.duplicate()
	result._dash_direction = _dash_direction
	result._dash_distance_per_tick = _dash_distance_per_tick
	result._dash_end_tick = _dash_end_tick
	result._content_hash = _content_hash
	result._configured = _configured
	return result


func _handle_event(event: RefCounted) -> Array:
	if event.event_type() != "event.hit":
		return []
	var types: Array = ["event.damage"]
	if event.payload().get("critical", false):
		types.append("event.critical")
	var emissions: Array = []
	for type: String in types:
		var request := EventRequest.new()
		Catalog._checked(request.configure(type, event.source_entity_id(), event.target_entity_id(),
			event.source_definition_id(), event.tags(), event.payload()))
		var emission := Emission.new()
		Catalog._checked(emission.configure("trigger.stormweaver.%s" % type, 0, 0, false, request))
		emissions.append(emission)
	return emissions
