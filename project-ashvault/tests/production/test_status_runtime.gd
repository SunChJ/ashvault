extends SceneTree

const CombatEventEmission = preload(
	"res://game/simulation/events/combat_event_emission.gd"
)
const CombatEventQueue = preload(
	"res://game/simulation/events/combat_event_queue.gd"
)
const CombatEventRequest = preload(
	"res://game/simulation/events/combat_event_request.gd"
)
const DamageComponent = preload(
	"res://game/simulation/combat/damage_component.gd"
)
const DamageContext = preload(
	"res://game/simulation/combat/damage_context.gd"
)
const DamageModifier = preload(
	"res://game/simulation/combat/damage_modifier.gd"
)
const DamagePipeline = preload(
	"res://game/simulation/combat/damage_pipeline.gd"
)
const StatusApplication = preload(
	"res://game/simulation/statuses/status_application.gd"
)
const StatusChange = preload(
	"res://game/simulation/statuses/status_change.gd"
)
const StatusDamageModifierTemplate = preload(
	"res://game/simulation/statuses/status_damage_modifier_template.gd"
)
const StatusDefinition = preload(
	"res://game/simulation/statuses/status_definition.gd"
)
const StatusRemoval = preload(
	"res://game/simulation/statuses/status_removal.gd"
)
const StatusTarget = preload(
	"res://game/simulation/statuses/status_target.gd"
)
const StatusWorld = preload(
	"res://game/simulation/statuses/status_world.gd"
)

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definitions_are_typed_immutable_and_validated()
	_test_application_stacking_refresh_and_expiry()
	_test_replace_and_extend_policies()
	_test_identity_and_tag_immunity()
	_test_cleanse_and_protected_removal()
	_test_shock_uses_the_damage_pipeline()
	_test_status_events_obey_proc_guards()
	_test_invalid_batches_roll_back()
	_test_mutation_order_and_replay_hash_are_deterministic()

	if failures.is_empty():
		print("Production status runtime tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_definitions_are_typed_immutable_and_validated() -> void:
	_assert_equal(StatusWorld.FIXED_TICKS_PER_SECOND, 60, "Status fixed-tick rate changed.")
	var shock := _shock_definition()
	_assert_equal(shock.status_id(), "status.shocked", "Shock identity is wrong.")
	_assert_equal(shock.max_stacks(), 3, "Shock stack limit is wrong.")
	_assert_equal(
		shock.refresh_policy(),
		StatusDefinition.RefreshPolicy.RESET,
		"Shock refresh policy is wrong."
	)
	_assert_contains(
		shock.configure(
			"status.changed",
			PackedStringArray(),
			1,
			1,
			1,
			StatusDefinition.StackPolicy.ADD,
			StatusDefinition.RefreshPolicy.KEEP,
			StatusDefinition.RemovalPolicy.CLEANSABLE,
			[]
		),
		"immutable",
		"Configured status definitions must reject mutation."
	)

	var invalid := StatusDefinition.new()
	_assert_contains(
		invalid.configure(
			"status.invalid",
			PackedStringArray(),
			5,
			4,
			1,
			StatusDefinition.StackPolicy.ADD,
			StatusDefinition.RefreshPolicy.KEEP,
			StatusDefinition.RemovalPolicy.CLEANSABLE,
			[]
		),
		"duration",
		"Status definitions must reject inverted duration bounds."
	)


func _test_application_stacking_refresh_and_expiry() -> void:
	var world := _world([_shock_definition()])
	var target := _target(2)
	var applied: RefCounted = world.advance_tick(
		[target],
		[_application(1, "status.shocked", 1, 2, 3, 2)]
	)
	_assert_true(applied.is_success(), "Initial status application must succeed.")
	_assert_equal(_change_outcomes(applied), [StatusChange.Outcome.APPLIED], "Apply outcome is wrong.")
	_assert_equal(world.stack_count(2, "status.shocked"), 2, "Initial stacks are wrong.")
	_assert_equal(world.expiry_tick(2, "status.shocked"), 4, "Initial expiry is wrong.")

	var stacked: RefCounted = world.advance_tick(
		[target],
		[_application(2, "status.shocked", 1, 2, 5, 2)]
	)
	_assert_equal(_change_outcomes(stacked), [StatusChange.Outcome.STACKED], "Stack outcome is wrong.")
	_assert_equal(world.stack_count(2, "status.shocked"), 3, "Stacks must clamp to the definition limit.")
	_assert_equal(world.expiry_tick(2, "status.shocked"), 7, "Reset refresh expiry is wrong.")

	for expected_tick in range(3, 7):
		var active: RefCounted = world.advance_tick([target], [])
		_assert_equal(active.tick(), expected_tick, "Status tick progression is wrong.")
		_assert_equal(active.changes().size(), 0, "Status expired too early.")
	var expired: RefCounted = world.advance_tick([target], [])
	_assert_equal(_change_outcomes(expired), [StatusChange.Outcome.EXPIRED], "Expiry outcome is wrong.")
	_assert_equal(world.stack_count(2, "status.shocked"), 0, "Expired status remained active.")


func _test_identity_and_tag_immunity() -> void:
	var world := _world([_shock_definition()])
	var result: RefCounted = world.advance_tick(
		[
			_target(2, PackedStringArray(["status.shocked"])),
			_target(3, PackedStringArray(), PackedStringArray(["status.ailment"])),
		],
		[
			_application(2, "status.shocked", 1, 3, 3, 1),
			_application(1, "status.shocked", 1, 2, 3, 1),
		]
	)

	_assert_true(result.is_success(), "Immunity is a resolved outcome, not a batch failure.")
	_assert_equal(
		_change_outcomes(result),
		[StatusChange.Outcome.IMMUNE, StatusChange.Outcome.IMMUNE],
		"Status or tag immunity was ignored."
	)
	_assert_equal(result.events().size(), 0, "Immune applications must not publish events.")
	_assert_equal(world.active_count(), 0, "Immune applications created active state.")


func _test_replace_and_extend_policies() -> void:
	var definition := StatusDefinition.new()
	_assert_equal(
		definition.configure(
			"status.extending",
			PackedStringArray(["status.test"]),
			1,
			10,
			5,
			StatusDefinition.StackPolicy.REPLACE,
			StatusDefinition.RefreshPolicy.EXTEND,
			StatusDefinition.RemovalPolicy.CLEANSABLE,
			[]
		),
		"",
		"Extending status definition must configure."
	)
	var world := _world([definition])
	var target := _target(2)
	world.advance_tick(
		[target],
		[_application(1, "status.extending", 1, 2, 2, 4)]
	)
	var replaced: RefCounted = world.advance_tick(
		[target],
		[_application(2, "status.extending", 1, 2, 3, 2)]
	)

	_assert_equal(_change_outcomes(replaced), [StatusChange.Outcome.STACKED], "Replace policy failed.")
	_assert_equal(world.stack_count(2, "status.extending"), 2, "Replace policy retained old stacks.")
	_assert_equal(world.expiry_tick(2, "status.extending"), 6, "Extend refresh policy failed.")


func _test_cleanse_and_protected_removal() -> void:
	var shock := _shock_definition()
	var ward := _ward_definition()
	var world := _world([shock, ward])
	var target := _target(2)
	world.advance_tick(
		[target],
		[
			_application(1, "status.shocked", 1, 2, 5, 1),
			_application(2, "status.static_ward", 1, 2, 5, 1),
		]
	)
	var unchanged: RefCounted = world.advance_tick(
		[target],
		[_application(3, "status.static_ward", 1, 2, 1, 1)]
	)
	_assert_equal(
		_change_outcomes(unchanged),
		[StatusChange.Outcome.UNCHANGED],
		"Maximum-stack and keep-duration policies changed Ward."
	)
	_assert_equal(unchanged.events().size(), 0, "Unchanged applications must not publish events.")
	var cleansed: RefCounted = world.advance_tick(
		[target],
		[],
		[
			_removal(4, 1, 2, "status.shocked", StatusRemoval.Reason.CLEANSE),
			_removal(5, 1, 2, "status.static_ward", StatusRemoval.Reason.CLEANSE),
		]
	)

	_assert_equal(
		_change_outcomes(cleansed),
		[StatusChange.Outcome.CLEANSED, StatusChange.Outcome.PROTECTED],
		"Cleanse policies resolved incorrectly."
	)
	_assert_equal(world.stack_count(2, "status.shocked"), 0, "Cleansed status remained active.")
	_assert_equal(world.stack_count(2, "status.static_ward"), 1, "Protected status was cleansed.")

	var forced: RefCounted = world.advance_tick(
		[],
		[],
		[_removal(6, 1, 2, "status.static_ward", StatusRemoval.Reason.FORCED)]
	)
	_assert_equal(
		_change_outcomes(forced),
		[StatusChange.Outcome.REMOVED],
		"Forced removal must survive target loss."
	)
	_assert_equal(world.active_count(), 0, "Forced removal left active state.")


func _test_shock_uses_the_damage_pipeline() -> void:
	var world := _world([_shock_definition()])
	world.advance_tick(
		[_target(2)],
		[_application(1, "status.shocked", 1, 2, 5, 2)]
	)
	var modifiers: Array = world.damage_modifiers_for(2)
	_assert_equal(modifiers.size(), 1, "Shock must publish one damage modifier.")
	_assert_equal(
		modifiers[0].operation(),
		DamageModifier.Operation.CONDITIONAL,
		"Shock must enter the conditional damage stage."
	)

	var component := DamageComponent.new()
	_assert_equal(
		component.configure("damage.lightning", 100.0, "ability.chain_lightning"),
		"",
		"Damage component must configure."
	)
	var context := DamageContext.new()
	_assert_equal(
		context.configure(
			1,
			2,
			"ability.chain_lightning",
			1,
			PackedStringArray(["damage.lightning"]),
			[component],
			modifiers,
			world.active_condition_ids(2),
			0.0,
			1.0,
			1.0
		),
		"",
		"Shock damage context must configure."
	)
	var resolution: RefCounted = DamagePipeline.resolve(context)
	_assert_true(resolution.is_success(), "Shock damage must resolve through DamagePipeline.")
	_assert_float(resolution.result().total_damage(), 130.0, "Two Shock stacks must add 30% damage.")
	_assert_equal(
		resolution.result().contributing_source_ids(),
		PackedStringArray(["ability.chain_lightning", "status.shocked.damage_taken"]),
		"Shock modifier provenance is wrong."
	)


func _test_status_events_obey_proc_guards() -> void:
	var world := _world([_shock_definition()])
	var tick_result: RefCounted = world.advance_tick(
		[_target(2)],
		[_application(1, "status.shocked", 1, 2, 3, 1)]
	)
	_assert_equal(tick_result.events().size(), 1, "Applied status must publish one event request.")
	var queue := CombatEventQueue.new()
	_assert_equal(queue.configure(), "", "Combat event queue must configure.")
	queue.enqueue_root(tick_result.events()[0])
	var processed: RefCounted = queue.process_tick(1, Callable(self, "_emit_status_cycle"))

	_assert_true(processed.is_success(), "A guarded status proc cycle is a bounded outcome.")
	_assert_equal(processed.processed_events().size(), 2, "Status proc self-reentry was not stopped.")
	_assert_diagnostic(
		processed.diagnostics(),
		"proc.self_reentry_denied",
		"Status events must retain combat queue self-reentry guards."
	)


func _test_invalid_batches_roll_back() -> void:
	var world := _world([_shock_definition()])
	var target := _target(2)
	world.advance_tick(
		[target],
		[_application(1, "status.shocked", 1, 2, 3, 1)]
	)
	var before_hash: String = world.state_hash()
	var rejected: RefCounted = world.advance_tick(
		[target],
		[
			_application(2, "status.shocked", 1, 2, 3, 1),
			_application(2, "status.shocked", 1, 2, 3, 1),
		]
	)

	_assert_true(not rejected.is_success(), "Duplicate mutation IDs must fail the batch.")
	_assert_equal(world.tick(), 1, "Rejected status batch advanced the tick.")
	_assert_equal(world.state_hash(), before_hash, "Rejected status batch changed state.")
	_assert_equal(rejected.active_count(), 1, "Rejected result reported the wrong active count.")


func _test_mutation_order_and_replay_hash_are_deterministic() -> void:
	var definitions := [_shock_definition(), _ward_definition()]
	var left := _world(definitions)
	var right := _world(definitions)
	var target := _target(2)
	var mutations := [
		_application(2, "status.static_ward", 1, 2, 4, 1),
		_application(1, "status.shocked", 1, 2, 4, 1),
	]
	var left_result: RefCounted = left.advance_tick([target], mutations)
	var reversed := mutations.duplicate()
	reversed.reverse()
	var right_result: RefCounted = right.advance_tick([target], reversed)

	_assert_equal(
		_change_keys(left_result),
		_change_keys(right_result),
		"Mutation input order changed outcomes."
	)
	_assert_equal(left.active_values(), right.active_values(), "Replay state diverged.")
	_assert_equal(left.state_hash(), right.state_hash(), "Replay hashes diverged.")
	_assert_equal(
		left.state_hash(),
		"ff66151a9d113521803af94ce9d354f3e21c21efc08c45be09f3ba05d561f61c",
		"Status state hash contract changed."
	)


func _shock_definition() -> RefCounted:
	var modifier := StatusDamageModifierTemplate.new()
	_assert_equal(
		modifier.configure(
			"damage.lightning",
			0.15,
			"status.shocked.damage_taken",
			100
		),
		"",
		"Shock damage modifier template must configure."
	)
	var definition := StatusDefinition.new()
	_assert_equal(
		definition.configure(
			"status.shocked",
			PackedStringArray(["status.ailment", "status.lightning"]),
			1,
			600,
			3,
			StatusDefinition.StackPolicy.ADD,
			StatusDefinition.RefreshPolicy.RESET,
			StatusDefinition.RemovalPolicy.CLEANSABLE,
			[modifier]
		),
		"",
		"Shock definition must configure."
	)
	return definition


func _ward_definition() -> RefCounted:
	var definition := StatusDefinition.new()
	_assert_equal(
		definition.configure(
			"status.static_ward",
			PackedStringArray(["status.buff", "status.defensive"]),
			1,
			600,
			1,
			StatusDefinition.StackPolicy.MAXIMUM,
			StatusDefinition.RefreshPolicy.KEEP,
			StatusDefinition.RemovalPolicy.PROTECTED,
			[]
		),
		"",
		"Ward definition must configure."
	)
	return definition


func _world(definitions: Array) -> RefCounted:
	var world := StatusWorld.new()
	_assert_equal(world.configure(definitions, 0), "", "Status world must configure.")
	return world


func _target(
	entity_id: int,
	immune_status_ids: PackedStringArray = PackedStringArray(),
	immune_tags: PackedStringArray = PackedStringArray()
) -> RefCounted:
	var target := StatusTarget.new()
	_assert_equal(
		target.configure(entity_id, true, immune_status_ids, immune_tags),
		"",
		"Status target must configure."
	)
	return target


func _application(
	mutation_id: int,
	status_id: String,
	source_entity_id: int,
	target_entity_id: int,
	duration_ticks: int,
	stacks: int
) -> RefCounted:
	var application := StatusApplication.new()
	_assert_equal(
		application.configure(
			mutation_id,
			status_id,
			source_entity_id,
			target_entity_id,
			duration_ticks,
			stacks
		),
		"",
		"Status application must configure."
	)
	return application


func _removal(
	mutation_id: int,
	source_entity_id: int,
	target_entity_id: int,
	status_id: String,
	reason: int
) -> RefCounted:
	var removal := StatusRemoval.new()
	_assert_equal(
		removal.configure(
			mutation_id,
			source_entity_id,
			target_entity_id,
			status_id,
			reason
		),
		"",
		"Status removal must configure."
	)
	return removal


func _emit_status_cycle(event: RefCounted) -> Array:
	if event.event_type() != "event.status_applied":
		return []
	var request := CombatEventRequest.new()
	var error: String = request.configure(
		"event.status_applied",
		event.source_entity_id(),
		event.target_entity_id(),
		event.source_definition_id(),
		event.tags(),
		event.payload()
	)
	_assert_equal(error, "", "Status proc request must configure.")
	var emission := CombatEventEmission.new()
	error = emission.configure("trigger.status.reapply", 0, 0, false, request)
	_assert_equal(error, "", "Status proc emission must configure.")
	return [emission]


func _change_outcomes(result: RefCounted) -> Array:
	var values: Array = []
	for change: RefCounted in result.changes():
		values.append(change.outcome())
	return values


func _change_keys(result: RefCounted) -> Array:
	var values: Array = []
	for change: RefCounted in result.changes():
		values.append([change.mutation_id(), change.status_id(), change.outcome()])
	return values


func _assert_diagnostic(diagnostics: Array, code: String, message: String) -> void:
	for diagnostic: Dictionary in diagnostics:
		if diagnostic.get("code", "") == code:
			return
	failures.append(message)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_contains(actual: String, expected: String, message: String) -> void:
	if not actual.contains(expected):
		failures.append("%s Expected '%s' in '%s'." % [message, expected, actual])
