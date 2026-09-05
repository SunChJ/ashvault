class_name StatusWorld
extends RefCounted

const ApplicationContract = preload(
	"res://game/simulation/statuses/status_application.gd"
)
const Change = preload("res://game/simulation/statuses/status_change.gd")
const CombatEventRequest = preload(
	"res://game/simulation/events/combat_event_request.gd"
)
const DefinitionContract = preload(
	"res://game/simulation/statuses/status_definition.gd"
)
const RemovalContract = preload(
	"res://game/simulation/statuses/status_removal.gd"
)
const RuntimeState = preload(
	"res://game/simulation/statuses/status_runtime_state.gd"
)
const TargetContract = preload(
	"res://game/simulation/statuses/status_target.gd"
)
const TickResult = preload(
	"res://game/simulation/statuses/status_tick_result.gd"
)

const FIXED_TICKS_PER_SECOND := 60
const STATE_HASH_SCHEMA_VERSION := 1

var _definitions: Dictionary = {}
var _states: Dictionary = {}
var _tick := -1
var _last_mutation_id := 0
var _state_hash := ""
var _is_configured := false


func configure(definitions: Array, initial_tick: int = 0) -> String:
	if _is_configured:
		return "Status world is already configured."
	if initial_tick < 0:
		return "Status initial tick must be non-negative."
	var definition_result := _validated_definitions(definitions)
	if not definition_result["error"].is_empty():
		return definition_result["error"]
	_definitions = definition_result["definitions"]
	_states = {}
	_tick = initial_tick
	_last_mutation_id = 0
	_state_hash = ""
	_is_configured = true
	return ""


func tick() -> int:
	return _tick


func active_count() -> int:
	return _states.size()


func stack_count(target_entity_id: int, status_id: String) -> int:
	var state: RefCounted = _states.get(_state_key(target_entity_id, status_id))
	return 0 if state == null else state.stack_count()


func expiry_tick(target_entity_id: int, status_id: String) -> int:
	var state: RefCounted = _states.get(_state_key(target_entity_id, status_id))
	return -1 if state == null else state.expiry_tick()


func active_condition_ids(target_entity_id: int) -> PackedStringArray:
	var result := PackedStringArray()
	for state: RefCounted in _sorted_states(_states):
		if state.target_entity_id() == target_entity_id:
			result.append(state.status_id())
	return result


func damage_modifiers_for(target_entity_id: int) -> Array:
	var result: Array = []
	for state: RefCounted in _sorted_states(_states):
		if state.target_entity_id() != target_entity_id:
			continue
		var definition: Resource = _definitions[state.status_id()]
		result.append_array(definition.damage_modifiers(state.stack_count()))
	return result


func active_values() -> Array:
	var result: Array = []
	for state: RefCounted in _sorted_states(_states):
		result.append(state.canonical_values())
	return result


func state_hash() -> String:
	if not _is_configured:
		return ""
	if _state_hash.is_empty():
		var canonical := [
			STATE_HASH_SCHEMA_VERSION,
			FIXED_TICKS_PER_SECOND,
			_tick,
			_last_mutation_id,
			_definition_values(),
			active_values(),
		]
		var context := HashingContext.new()
		var start_error := context.start(HashingContext.HASH_SHA256)
		assert(start_error == OK, "SHA-256 hashing must be available.")
		var update_error := context.update(JSON.stringify(canonical).to_utf8_buffer())
		assert(update_error == OK, "Status state hashing must accept UTF-8 input.")
		_state_hash = context.finish().hex_encode()
	return _state_hash


func advance_tick(
	targets: Array,
	applications: Array = [],
	removals: Array = []
) -> RefCounted:
	var expected_tick := _tick + 1
	if not _is_configured:
		return _rejected(expected_tick, "status.unconfigured", "Status world is not configured.")
	var target_result := _validated_targets(targets)
	if not target_result["error"].is_empty():
		return _rejected(expected_tick, "status.invalid_targets", target_result["error"])
	var mutation_result := _validated_mutations(applications, removals)
	if not mutation_result["error"].is_empty():
		return _rejected(expected_tick, "status.invalid_mutations", mutation_result["error"])

	var staged_states: Dictionary = {}
	for state_key: String in _states:
		staged_states[state_key] = _states[state_key]._duplicate_state()
	var changes: Array = []
	var events: Array = []
	_expire_states(staged_states, expected_tick, changes)
	var target_by_id: Dictionary = target_result["targets"]
	var staged_last_mutation_id := _last_mutation_id
	for mutation: Dictionary in mutation_result["mutations"]:
		var value: RefCounted = mutation["value"]
		staged_last_mutation_id = value.mutation_id()
		if mutation["kind"] == 0:
			_apply_application(
				staged_states,
				target_by_id,
				value,
				expected_tick,
				changes,
				events
			)
		else:
			_apply_removal(staged_states, target_by_id, value, expected_tick, changes)

	_states = staged_states
	_tick = expected_tick
	_last_mutation_id = staged_last_mutation_id
	_state_hash = ""
	return _result(_tick, true, changes, events, _states.size(), [])


func _apply_application(
	states: Dictionary,
	targets: Dictionary,
	application: RefCounted,
	current_tick: int,
	changes: Array,
	events: Array
) -> void:
	var definition: Resource = _definitions[application.status_id()]
	var target: RefCounted = targets.get(application.target_entity_id())
	if target == null or not target.is_alive():
		changes.append(_application_change(application, current_tick, Change.Outcome.TARGET_UNAVAILABLE))
		return
	if target.is_immune_to(definition):
		changes.append(_application_change(application, current_tick, Change.Outcome.IMMUNE))
		return

	var key := _state_key(application.target_entity_id(), application.status_id())
	var state: RefCounted = states.get(key)
	if state == null:
		var stack_count: int = mini(application.stacks(), definition.max_stacks())
		var expiry: int = current_tick + application.duration_ticks()
		state = RuntimeState.new()
		state._configure(
			application.target_entity_id(),
			application.status_id(),
			application.source_entity_id(),
			stack_count,
			expiry,
			application.mutation_id()
		)
		states[key] = state
		var change := _change(
			current_tick,
			application.mutation_id(),
			application.status_id(),
			application.source_entity_id(),
			application.target_entity_id(),
			Change.Outcome.APPLIED,
			0,
			stack_count,
			-1,
			expiry
		)
		changes.append(change)
		events.append(_status_applied_event(definition, change))
		return

	var previous_stacks: int = state.stack_count()
	var previous_expiry: int = state.expiry_tick()
	var next_stacks := _resolved_stacks(definition, previous_stacks, application.stacks())
	var next_expiry := _resolved_expiry(
		definition,
		previous_expiry,
		current_tick,
		application.duration_ticks()
	)
	var outcome := Change.Outcome.UNCHANGED
	if next_stacks != previous_stacks:
		outcome = Change.Outcome.STACKED
	elif next_expiry != previous_expiry:
		outcome = Change.Outcome.REFRESHED
	state._apply(
		application.source_entity_id(),
		next_stacks,
		next_expiry,
		application.mutation_id()
	)
	var change := _change(
		current_tick,
		application.mutation_id(),
		application.status_id(),
		application.source_entity_id(),
		application.target_entity_id(),
		outcome,
		previous_stacks,
		next_stacks,
		previous_expiry,
		next_expiry
	)
	changes.append(change)
	if outcome != Change.Outcome.UNCHANGED:
		events.append(_status_applied_event(definition, change))


func _apply_removal(
	states: Dictionary,
	targets: Dictionary,
	removal: RefCounted,
	current_tick: int,
	changes: Array
) -> void:
	var key := _state_key(removal.target_entity_id(), removal.status_id())
	var state: RefCounted = states.get(key)
	var target: RefCounted = targets.get(removal.target_entity_id())
	if state == null:
		changes.append(_removal_change(removal, current_tick, null, Change.Outcome.MISSING))
		return
	if (
		removal.reason() != RemovalContract.Reason.FORCED
		and (target == null or not target.is_alive())
	):
		changes.append(_removal_change(removal, current_tick, state, Change.Outcome.TARGET_UNAVAILABLE))
		return
	var definition: Resource = _definitions[removal.status_id()]
	if (
		removal.reason() == RemovalContract.Reason.CLEANSE
		and definition.removal_policy() == DefinitionContract.RemovalPolicy.PROTECTED
	):
		changes.append(_removal_change(removal, current_tick, state, Change.Outcome.PROTECTED))
		return
	var outcome := (
		Change.Outcome.CLEANSED
		if removal.reason() == RemovalContract.Reason.CLEANSE
		else Change.Outcome.REMOVED
	)
	changes.append(_removal_change(removal, current_tick, state, outcome))
	states.erase(key)


func _expire_states(states: Dictionary, current_tick: int, changes: Array) -> void:
	for state: RefCounted in _sorted_states(states):
		if current_tick < state.expiry_tick():
			continue
		changes.append(_change(
			current_tick,
			0,
			state.status_id(),
			state.source_entity_id(),
			state.target_entity_id(),
			Change.Outcome.EXPIRED,
			state.stack_count(),
			0,
			state.expiry_tick(),
			-1
		))
		states.erase(_state_key(state.target_entity_id(), state.status_id()))


func _validated_definitions(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is DefinitionContract or not value.is_configured():
			return {"definitions": {}, "error": "Status definition at index %d is not configured." % index}
		if result.has(value.status_id()):
			return {"definitions": {}, "error": "Duplicate status definition '%s'." % value.status_id()}
		result[value.status_id()] = value
	return {"definitions": result, "error": ""}


func _validated_targets(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is TargetContract or not value.is_configured():
			return {"targets": {}, "error": "Status target at index %d is not configured." % index}
		if result.has(value.entity_id()):
			return {"targets": {}, "error": "Duplicate status target %d." % value.entity_id()}
		result[value.entity_id()] = value
	return {"targets": result, "error": ""}


func _validated_mutations(applications: Array, removals: Array) -> Dictionary:
	var observed: Dictionary = {}
	var result: Array = []
	for collection_index in 2:
		var values: Array = applications if collection_index == 0 else removals
		for index in values.size():
			var value: Variant = values[index]
			var matches_contract := (
				(collection_index == 0 and value is ApplicationContract)
				or (collection_index == 1 and value is RemovalContract)
			)
			if not matches_contract or not value.is_configured():
				return {"mutations": [], "error": "Status mutation at index %d is not configured." % index}
			if value.mutation_id() <= _last_mutation_id or observed.has(value.mutation_id()):
				return {
					"mutations": [],
					"error": (
						"Status mutation ID %d must be unique and greater than %d."
						% [value.mutation_id(), _last_mutation_id]
					),
				}
			if not _definitions.has(value.status_id()):
				return {"mutations": [], "error": "Unknown status definition '%s'." % value.status_id()}
			if (
				collection_index == 0
				and not _definitions[value.status_id()].accepts_duration(value.duration_ticks())
			):
				return {
					"mutations": [],
					"error": "Status '%s' rejected duration %d." % [value.status_id(), value.duration_ticks()],
				}
			observed[value.mutation_id()] = true
			result.append({"kind": collection_index, "value": value})
	result.sort_custom(_mutation_precedes)
	return {"mutations": result, "error": ""}


static func _resolved_stacks(definition: Resource, current: int, incoming: int) -> int:
	match definition.stack_policy():
		DefinitionContract.StackPolicy.ADD:
			return mini(current + incoming, definition.max_stacks())
		DefinitionContract.StackPolicy.REPLACE:
			return mini(incoming, definition.max_stacks())
		DefinitionContract.StackPolicy.MAXIMUM:
			return mini(maxi(current, incoming), definition.max_stacks())
	return current


static func _resolved_expiry(
	definition: Resource,
	current_expiry: int,
	current_tick: int,
	duration_ticks: int
) -> int:
	match definition.refresh_policy():
		DefinitionContract.RefreshPolicy.KEEP:
			return current_expiry
		DefinitionContract.RefreshPolicy.RESET:
			return current_tick + duration_ticks
		DefinitionContract.RefreshPolicy.EXTEND:
			return current_expiry + duration_ticks
	return current_expiry


static func _application_change(
	application: RefCounted,
	current_tick: int,
	outcome: int
) -> RefCounted:
	return _change(
		current_tick,
		application.mutation_id(),
		application.status_id(),
		application.source_entity_id(),
		application.target_entity_id(),
		outcome,
		0,
		0,
		-1,
		-1
	)


static func _removal_change(
	removal: RefCounted,
	current_tick: int,
	state: RefCounted,
	outcome: int
) -> RefCounted:
	var stacks: int = 0 if state == null else state.stack_count()
	var expiry: int = -1 if state == null else state.expiry_tick()
	return _change(
		current_tick,
		removal.mutation_id(),
		removal.status_id(),
		removal.source_entity_id(),
		removal.target_entity_id(),
		outcome,
		stacks,
		stacks if outcome in [Change.Outcome.PROTECTED, Change.Outcome.TARGET_UNAVAILABLE] else 0,
		expiry,
		expiry if outcome in [Change.Outcome.PROTECTED, Change.Outcome.TARGET_UNAVAILABLE] else -1
	)


static func _change(
	tick_value: int,
	mutation_id: int,
	status_id: String,
	source_entity_id: int,
	target_entity_id: int,
	outcome: int,
	previous_stacks: int,
	current_stacks: int,
	previous_expiry: int,
	current_expiry: int
) -> RefCounted:
	var result := Change.new()
	result._configure(
		tick_value,
		mutation_id,
		status_id,
		source_entity_id,
		target_entity_id,
		outcome,
		previous_stacks,
		current_stacks,
		previous_expiry,
		current_expiry
	)
	return result


static func _status_applied_event(definition: Resource, change: RefCounted) -> RefCounted:
	var result := CombatEventRequest.new()
	var error: String = result.configure(
		"event.status_applied",
		change.source_entity_id(),
		change.target_entity_id(),
		definition.status_id(),
		definition.tags(),
		{
			"mutation_id": change.mutation_id(),
			"outcome": Change.outcome_name(change.outcome()),
			"stacks": change.current_stacks(),
			"expiry_tick": change.current_expiry_tick(),
		}
	)
	assert(error.is_empty())
	return result


func _definition_values() -> Array:
	var ids: Array = _definitions.keys()
	ids.sort()
	var result: Array = []
	for status_id: String in ids:
		result.append(_definitions[status_id].canonical_values())
	return result


static func _sorted_states(values: Dictionary) -> Array:
	var result: Array = values.values()
	result.sort_custom(_state_precedes)
	return result


static func _state_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.target_entity_id() != right.target_entity_id():
		return left.target_entity_id() < right.target_entity_id()
	return left.status_id() < right.status_id()


static func _mutation_precedes(left: Dictionary, right: Dictionary) -> bool:
	return left["value"].mutation_id() < right["value"].mutation_id()


static func _state_key(target_entity_id: int, status_id: String) -> String:
	return "%d|%s" % [target_entity_id, status_id]


func _rejected(tick_value: int, code: String, message: String) -> RefCounted:
	return _result(
		tick_value,
		false,
		[],
		[],
		_states.size(),
		[{"code": code, "tick": tick_value, "message": message}]
	)


static func _result(
	tick_value: int,
	is_success: bool,
	changes: Array,
	events: Array,
	active_count_value: int,
	diagnostics: Array
) -> RefCounted:
	var result := TickResult.new()
	result._configure(
		tick_value,
		is_success,
		changes,
		events,
		active_count_value,
		diagnostics
	)
	return result


# Tick methods copy changed values before mutation; staging can share immutable inputs.
func _duplicate_world() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._tick = _tick
	result._definitions = _definitions.duplicate()
	result._states = _states.duplicate()
	result._last_mutation_id = _last_mutation_id
	result._state_hash = _state_hash
	result._is_configured = _is_configured
	return result
