class_name CombatEventQueue
extends RefCounted

const CombatEventContract = preload("res://game/simulation/events/combat_event.gd")
const EmissionContract = preload("res://game/simulation/events/combat_event_emission.gd")
const ProcessResult = preload("res://game/simulation/events/combat_event_process_result.gd")
const RequestContract = preload("res://game/simulation/events/combat_event_request.gd")

const DEFAULT_MAX_DEPTH := 8
const DEFAULT_TICK_BUDGET := 4096

var _max_depth := DEFAULT_MAX_DEPTH
var _tick_budget := DEFAULT_TICK_BUDGET
var _next_event_id := 1
var _pending: Array = []
var _budget_tick := -1
var _processed_in_budget_tick := 0
var _is_processing := false
var _is_configured := false


func configure(
	max_depth_value: int = DEFAULT_MAX_DEPTH,
	tick_budget_value: int = DEFAULT_TICK_BUDGET,
	first_event_id: int = 1
) -> String:
	if _is_configured:
		return "Combat event queue is already configured."
	if max_depth_value < 0:
		return "Combat event maximum depth must be non-negative."
	if tick_budget_value <= 0:
		return "Combat event tick budget must be positive."
	if first_event_id <= 0:
		return "First combat event ID must be positive."
	_max_depth = max_depth_value
	_tick_budget = tick_budget_value
	_next_event_id = first_event_id
	_is_configured = true
	return ""


func max_depth() -> int:
	return _max_depth


func tick_budget() -> int:
	return _tick_budget


func pending_count() -> int:
	return _pending.size()


func enqueue_root(request: Variant) -> RefCounted:
	if (
		not _is_configured
		or _is_processing
		or not request is RequestContract
		or not request.is_configured()
	):
		return null
	var event_id := _allocate_event_id()
	var event := _publish_event(
		event_id,
		event_id,
		0,
		request,
		PackedStringArray()
	)
	_pending.append(event)
	return event


func process_tick(tick: int, handler: Callable) -> RefCounted:
	if not _is_configured:
		return _result(
			tick,
			false,
			[],
			[_diagnostic("event.queue_unconfigured", tick, null, "Combat event queue is not configured.")]
		)
	if tick < 0:
		return _result(
			tick,
			false,
			[],
			[_diagnostic("event.invalid_tick", tick, null, "Combat event tick must be non-negative.")]
		)
	if _budget_tick >= 0 and tick < _budget_tick:
		return _result(
			tick,
			false,
			[],
			[_diagnostic(
				"event.tick_regression",
				tick,
				null,
				"Combat event tick %d cannot precede already processed tick %d."
				% [tick, _budget_tick]
			)]
		)
	if not handler.is_valid() or _is_processing:
		return _result(
			tick,
			false,
			[],
			[_diagnostic("event.invalid_handler", tick, null, "Combat event handler is not callable.")]
		)

	var processed: Array = []
	var diagnostics: Array = []
	var failed := false
	if tick > _budget_tick:
		_budget_tick = tick
		_processed_in_budget_tick = 0
	_is_processing = true
	while not _pending.is_empty():
		if _processed_in_budget_tick >= _tick_budget:
			var next_event: RefCounted = _pending[0]
			diagnostics.append(_diagnostic(
				"event.budget_exhausted",
				tick,
				next_event,
				"Combat event tick budget %d exhausted with %d event(s) pending."
				% [_tick_budget, _pending.size()]
			))
			failed = true
			break

		var event: RefCounted = _pending.pop_front()
		processed.append(event)
		_processed_in_budget_tick += 1
		var emitted: Variant = handler.call(event)
		if not emitted is Array:
			diagnostics.append(_diagnostic(
				"event.invalid_emission",
				tick,
				event,
				"Combat event handler must return an Array of configured emissions."
			))
			failed = true
			break
		var validation_error := _validate_emissions(emitted)
		if not validation_error.is_empty():
			diagnostics.append(_diagnostic(
				"event.invalid_emission",
				tick,
				event,
				validation_error
			))
			failed = true
			break
		var emissions: Array = emitted.duplicate()
		emissions.sort_custom(_emission_precedes)
		for emission: RefCounted in emissions:
			_expand(event, emission, tick, diagnostics)
	_is_processing = false
	return _result(tick, not failed, processed, diagnostics)


func _expand(
	parent: RefCounted,
	emission: RefCounted,
	tick: int,
	diagnostics: Array
) -> void:
	var trace: PackedStringArray = parent.trigger_trace()
	if trace.has(emission.trigger_id()) and not emission.allows_self_reentry():
		var diagnostic := _diagnostic(
			"proc.self_reentry_denied",
			tick,
			parent,
			"Trigger '%s' cannot re-enter chain %d by default."
			% [emission.trigger_id(), parent.chain_id()]
		)
		diagnostic["trigger_id"] = emission.trigger_id()
		diagnostics.append(diagnostic)
		return
	var child_depth: int = parent.depth() + 1
	if child_depth > _max_depth:
		var diagnostic := _diagnostic(
			"proc.depth_exhausted",
			tick,
			parent,
			"Trigger '%s' attempted depth %d beyond maximum depth %d."
			% [emission.trigger_id(), child_depth, _max_depth]
		)
		diagnostic["trigger_id"] = emission.trigger_id()
		diagnostic["attempted_depth"] = child_depth
		diagnostics.append(diagnostic)
		return
	trace.append(emission.trigger_id())
	var child := _publish_event(
		_allocate_event_id(),
		parent.chain_id(),
		child_depth,
		emission.request(),
		trace
	)
	_pending.append(child)


func _allocate_event_id() -> int:
	var result := _next_event_id
	_next_event_id += 1
	return result


func _publish_event(
	event_id: int,
	chain_id: int,
	depth: int,
	request: RefCounted,
	trigger_trace: PackedStringArray
) -> RefCounted:
	var event := CombatEventContract.new()
	var error: String = event._publish(
		event_id,
		chain_id,
		depth,
		request,
		trigger_trace
	)
	assert(error.is_empty())
	return event


static func _validate_emissions(emissions: Array) -> String:
	var observed: Dictionary = {}
	for index in emissions.size():
		var emission: Variant = emissions[index]
		if not emission is EmissionContract or not emission.is_configured():
			return "Combat event emission at index %d is not configured." % index
		var identity: String = emission.identity_key()
		if observed.has(identity):
			return "Duplicate combat event emission '%s'." % identity
		observed[identity] = true
	return ""


static func _emission_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.priority() != right.priority():
		return left.priority() > right.priority()
	if left.trigger_id() != right.trigger_id():
		return left.trigger_id() < right.trigger_id()
	return left.sequence() < right.sequence()


static func _diagnostic(
	code: String,
	tick: int,
	event: Variant,
	message: String
) -> Dictionary:
	var result := {
		"code": code,
		"tick": tick,
		"message": message,
	}
	if event != null:
		result["event_id"] = event.event_id()
		result["chain_id"] = event.chain_id()
		result["depth"] = event.depth()
	return result


func _result(
	tick: int,
	is_success: bool,
	processed: Array,
	diagnostics: Array
) -> RefCounted:
	var result := ProcessResult.new()
	result._configure(tick, is_success, processed, diagnostics, _pending.size())
	return result
