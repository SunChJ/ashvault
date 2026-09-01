extends SceneTree

const CombatEvent = preload("res://game/simulation/events/combat_event.gd")
const CombatEventEmission = preload("res://game/simulation/events/combat_event_emission.gd")
const CombatEventQueue = preload("res://game/simulation/events/combat_event_queue.gd")
const CombatEventRequest = preload("res://game/simulation/events/combat_event_request.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_event_contract_and_immutable_payload()
	_test_on_hit_on_critical_and_on_kill_expand_fifo()
	_test_emission_order_is_stable()
	_test_self_reentry_is_denied_by_default()
	_test_explicit_reentry_stops_after_depth_eight()
	_test_budget_exhaustion_fails_and_retains_pending_events()
	_test_invalid_handler_output_fails_with_a_diagnostic()
	_test_process_results_do_not_expose_mutable_storage()

	if failures.is_empty():
		print("Production combat event tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_event_contract_and_immutable_payload() -> void:
	_assert_equal(
		CombatEvent.CORE_EVENT_TYPES,
		[
			"event.block",
			"event.cast",
			"event.critical",
			"event.damage",
			"event.death",
			"event.dodge",
			"event.hit",
			"event.item_dropped",
			"event.item_picked_up",
			"event.kill",
			"event.status_applied",
		],
		"Core event type IDs are a simulation compatibility contract."
	)
	var payload := {
		"damage": 12.5,
		"nested": {"flags": ["critical"]},
	}
	var request := _request(
		"event.damage",
		payload,
		PackedStringArray(["damage.lightning", "delivery.projectile"])
	)
	payload["damage"] = 999.0
	payload["nested"]["flags"].append("mutated")
	_assert_float(request.payload()["damage"], 12.5, "Request retained caller payload storage.")
	_assert_equal(
		request.tags(),
		PackedStringArray(["damage.lightning", "delivery.projectile"]),
		"Request tags must publish in stable order."
	)

	var invalid := CombatEventRequest.new()
	_assert_contains(
		invalid.configure(
			"event.damage", 1, 2, "ability.arc_bolt",
			PackedStringArray(), {"object": RefCounted.new()}
		),
		"JSON-compatible",
		"Payloads must reject runtime objects."
	)

	var queue := _queue()
	var event: RefCounted = queue.enqueue_root(request)
	_assert_equal(event.event_id(), 1, "Queue must assign the first event ID.")
	_assert_equal(event.chain_id(), 1, "Root chain ID must equal its event ID.")
	_assert_equal(event.depth(), 0, "Root events must start at depth zero.")
	_assert_equal(event.trigger_trace(), PackedStringArray(), "Root events must have an empty trigger trace.")
	var leaked: Dictionary = event.payload()
	leaked["damage"] = 777.0
	_assert_float(event.payload()["damage"], 12.5, "Event payload must be immutable to callers.")


func _test_on_hit_on_critical_and_on_kill_expand_fifo() -> void:
	var queue := _queue()
	queue.enqueue_root(_request("event.hit"))
	var result: RefCounted = queue.process_tick(7, Callable(self, "_expand_core_events"))

	_assert_true(result.is_success(), "Valid proc expansion must succeed.")
	_assert_true(result.is_drained(), "A bounded proc chain must fully drain.")
	var events: Array = result.processed_events()
	_assert_equal(
		_event_types(events),
		["event.hit", "event.critical", "event.kill", "event.item_dropped"],
		"On-hit, on-critical, and on-kill events must execute FIFO."
	)
	_assert_equal(_event_ids(events), [1, 2, 3, 4], "Event IDs must be monotonic.")
	_assert_equal(_chain_ids(events), [1, 1, 1, 1], "Children must inherit the root chain ID.")
	_assert_equal(_depths(events), [0, 1, 2, 3], "Child depth must increment exactly once.")


func _test_emission_order_is_stable() -> void:
	var first_queue := _queue()
	first_queue.enqueue_root(_request("event.hit"))
	var first: RefCounted = first_queue.process_tick(
		1,
		Callable(self, "_unordered_emissions")
	)
	var second_queue := _queue()
	second_queue.enqueue_root(_request("event.hit"))
	var second: RefCounted = second_queue.process_tick(
		1,
		Callable(self, "_reversed_unordered_emissions")
	)
	var expected := [
		"event.hit",
		"event.critical",
		"event.damage",
		"event.dodge",
		"event.block",
	]
	_assert_equal(_event_types(first.processed_events()), expected, "Emission precedence is wrong.")
	_assert_equal(
		_event_types(first.processed_events()),
		_event_types(second.processed_events()),
		"Handler collection order must not change event order."
	)


func _test_self_reentry_is_denied_by_default() -> void:
	var queue := _queue()
	queue.enqueue_root(_request("event.hit"))
	var result: RefCounted = queue.process_tick(1, Callable(self, "_emit_denied_cycle"))

	_assert_true(result.is_success(), "A guarded cycle is an expected bounded outcome.")
	_assert_equal(result.processed_events().size(), 2, "Self re-entry must stop after one child.")
	_assert_true(result.is_drained(), "Denied self re-entry must not leave pending work.")
	_assert_diagnostic(
		result.diagnostics(),
		"proc.self_reentry_denied",
		"Denied self re-entry must emit a diagnostic."
	)


func _test_explicit_reentry_stops_after_depth_eight() -> void:
	var queue := _queue()
	_assert_equal(queue.max_depth(), 8, "The default maximum proc depth must be eight.")
	queue.enqueue_root(_request("event.hit"))
	var result: RefCounted = queue.process_tick(1, Callable(self, "_emit_allowed_cycle"))
	var events: Array = result.processed_events()

	_assert_true(result.is_success(), "Depth guarding is an expected bounded outcome.")
	_assert_equal(events.size(), 9, "Depth zero through eight must be processable.")
	_assert_equal(events[-1].depth(), 8, "The last accepted event must be depth eight.")
	_assert_diagnostic(
		result.diagnostics(),
		"proc.depth_exhausted",
		"A depth-nine attempt must emit a diagnostic."
	)


func _test_budget_exhaustion_fails_and_retains_pending_events() -> void:
	var queue := _queue(8, 3)
	queue.enqueue_root(_request("event.hit"))
	var exhausted: RefCounted = queue.process_tick(1, Callable(self, "_emit_allowed_cycle"))

	_assert_true(not exhausted.is_success(), "Budget exhaustion must fail the tick result.")
	_assert_equal(exhausted.processed_events().size(), 3, "The queue exceeded its tick budget.")
	_assert_equal(exhausted.pending_count(), 1, "Budget exhaustion must retain pending events.")
	_assert_diagnostic(
		exhausted.diagnostics(),
		"event.budget_exhausted",
		"Budget exhaustion must emit a diagnostic."
	)
	var same_tick: RefCounted = queue.process_tick(1, Callable(self, "_emit_nothing"))
	_assert_true(not same_tick.is_success(), "Repeated processing must not reset the same tick budget.")
	_assert_equal(same_tick.processed_events().size(), 0, "Same-tick processing bypassed the budget.")
	_assert_equal(same_tick.pending_count(), 1, "Same-tick exhaustion lost pending work.")

	var recovered: RefCounted = queue.process_tick(2, Callable(self, "_emit_nothing"))
	_assert_true(recovered.is_success(), "A later tick must be able to inspect and drain retained work.")
	_assert_equal(recovered.processed_events().size(), 1, "The retained event was lost.")
	_assert_true(recovered.is_drained(), "Recovery tick must drain the queue.")


func _test_invalid_handler_output_fails_with_a_diagnostic() -> void:
	var queue := _queue()
	queue.enqueue_root(_request("event.hit"))
	var result: RefCounted = queue.process_tick(1, Callable(self, "_emit_invalid"))

	_assert_true(not result.is_success(), "Invalid handler emissions must fail processing.")
	_assert_diagnostic(
		result.diagnostics(),
		"event.invalid_emission",
		"Invalid handler emissions must be diagnosed."
	)


func _test_process_results_do_not_expose_mutable_storage() -> void:
	var queue := _queue()
	queue.enqueue_root(_request("event.hit"))
	var result: RefCounted = queue.process_tick(1, Callable(self, "_emit_nothing"))
	var events: Array = result.processed_events()
	var diagnostics: Array = result.diagnostics()
	events.clear()
	diagnostics.append({"code": "event.fake"})
	_assert_equal(result.processed_events().size(), 1, "Caller mutation changed processed events.")
	_assert_equal(result.diagnostics(), [], "Caller mutation changed diagnostics.")


func _expand_core_events(event: RefCounted) -> Array:
	match event.event_type():
		"event.hit":
			return [_emission("trigger.on_hit", 0, "event.critical")]
		"event.critical":
			return [_emission("trigger.on_critical", 0, "event.kill")]
		"event.kill":
			return [_emission("trigger.on_kill", 0, "event.item_dropped")]
	return []


func _unordered_emissions(event: RefCounted) -> Array:
	if event.depth() > 0:
		return []
	return [
		_emission("trigger.beta", 0, "event.block", 10),
		_emission("trigger.alpha", 1, "event.dodge", 10),
		_emission("trigger.high", 0, "event.critical", 20),
		_emission("trigger.alpha", 0, "event.damage", 10),
	]


func _reversed_unordered_emissions(event: RefCounted) -> Array:
	var result := _unordered_emissions(event)
	result.reverse()
	return result


func _emit_denied_cycle(_event: RefCounted) -> Array:
	return [_emission("trigger.loop", 0, "event.hit")]


func _emit_allowed_cycle(_event: RefCounted) -> Array:
	return [_emission("trigger.loop", 0, "event.hit", 0, true)]


func _emit_nothing(_event: RefCounted) -> Array:
	return []


func _emit_invalid(_event: RefCounted) -> Array:
	return [null]


func _queue(max_depth: int = 8, tick_budget: int = 4096) -> RefCounted:
	var queue := CombatEventQueue.new()
	var error: String = queue.configure(max_depth, tick_budget, 1)
	assert(error.is_empty(), error)
	return queue


func _request(
	event_type: String,
	payload: Dictionary = {},
	tags: PackedStringArray = PackedStringArray(["event.combat"])
) -> RefCounted:
	var request := CombatEventRequest.new()
	var error: String = request.configure(
		event_type,
		1,
		2,
		"ability.arc_bolt",
		tags,
		payload
	)
	assert(error.is_empty(), error)
	return request


func _emission(
	trigger_id: String,
	sequence: int,
	event_type: String,
	priority: int = 0,
	allow_self_reentry: bool = false
) -> RefCounted:
	var emission := CombatEventEmission.new()
	var error: String = emission.configure(
		trigger_id,
		priority,
		sequence,
		allow_self_reentry,
		_request(event_type)
	)
	assert(error.is_empty(), error)
	return emission


func _event_types(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event: RefCounted in events:
		result.append(event.event_type())
	return result


func _event_ids(events: Array) -> Array[int]:
	var result: Array[int] = []
	for event: RefCounted in events:
		result.append(event.event_id())
	return result


func _chain_ids(events: Array) -> Array[int]:
	var result: Array[int] = []
	for event: RefCounted in events:
		result.append(event.chain_id())
	return result


func _depths(events: Array) -> Array[int]:
	var result: Array[int] = []
	for event: RefCounted in events:
		result.append(event.depth())
	return result


func _assert_diagnostic(diagnostics: Array, code: String, message: String) -> void:
	for diagnostic: Dictionary in diagnostics:
		if diagnostic.get("code") == code:
			return
	failures.append("%s Expected diagnostic '%s' in %s." % [message, code, diagnostics])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_contains(actual: Variant, expected: String, message: String) -> void:
	var values: Array = Array(actual) if actual is PackedStringArray else [str(actual)]
	for value: Variant in values:
		if str(value).contains(expected):
			return
	failures.append("%s Expected '%s' in %s." % [message, expected, actual])
