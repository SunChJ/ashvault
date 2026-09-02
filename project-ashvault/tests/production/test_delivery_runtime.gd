extends SceneTree

const DeliveryDefinition = preload(
	"res://game/simulation/delivery/delivery_definition.gd"
)
const DeliveryRequest = preload(
	"res://game/simulation/delivery/delivery_request.gd"
)
const DeliveryTarget = preload(
	"res://game/simulation/delivery/delivery_target.gd"
)
const DeliveryWorld = preload(
	"res://game/simulation/delivery/delivery_world.gd"
)

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definitions_are_typed_and_immutable()
	_test_area_selection_is_inclusive_and_deterministic()
	_test_chain_recovers_from_target_loss_and_excludes_prior_targets()
	_test_projectiles_sweep_and_choose_earliest_contact()
	_test_projectile_lifetime_is_exact()
	_test_persistent_pulses_and_expiry_are_exact()
	_test_invalid_batches_roll_back_all_state()
	_test_input_order_does_not_change_results_or_hashes()
	_test_density_path_uses_compact_values()

	if failures.is_empty():
		print("Production delivery runtime tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_definitions_are_typed_and_immutable() -> void:
	var projectile := _projectile_definition("delivery.projectile.arc", 600.0, 1.0, 3, 2)
	_assert_equal(projectile.kind(), DeliveryDefinition.Kind.PROJECTILE, "Projectile kind is wrong.")
	_assert_float(projectile.speed_per_second(), 600.0, "Projectile speed is wrong.")
	_assert_equal(projectile.max_targets(), 2, "Projectile hit limit is wrong.")
	_assert_contains(
		projectile.configure_area("delivery.changed", 2.0, 1),
		"immutable",
		"Configured delivery definitions must reject mutation."
	)
	_assert_equal(projectile.definition_id(), "delivery.projectile.arc", "Mutation changed ID.")

	var invalid := DeliveryDefinition.new()
	_assert_contains(
		invalid.configure_chain("delivery.chain.invalid", 10.0, 0.0, 3),
		"positive",
		"Chain jump range must be positive."
	)
	_assert_true(not invalid.is_configured(), "Rejected definitions must remain unconfigured.")


func _test_area_selection_is_inclusive_and_deterministic() -> void:
	var world := _world()
	var area := _area_definition("delivery.area.nova", 10.0, 2)
	var request := _request(1, area, Vector2.ZERO)
	var result: RefCounted = world.advance_tick([
		_target(4, 1, Vector2(1.0, 0.0)),
		_target(3, 2, Vector2(6.0, 8.0)),
		_target(1, 1, Vector2.ZERO),
		_target(2, 2, Vector2(-6.0, -8.0)),
	], [request])

	_assert_true(result.is_success(), "Valid area request must resolve.")
	_assert_equal(_hit_targets(result), [2, 3], "Area ordering or inclusive boundary is wrong.")
	_assert_equal(result.active_count(), 0, "Instant areas must not allocate active state.")
	_assert_equal(result.hits()[0].runtime_id(), 0, "Instant hits must not claim runtime IDs.")


func _test_chain_recovers_from_target_loss_and_excludes_prior_targets() -> void:
	var world := _world()
	var chain := _chain_definition("delivery.chain.lightning", 15.0, 6.0, 3)
	var request := _request(7, chain, Vector2.ZERO, Vector2.ZERO, 99)
	var result: RefCounted = world.advance_tick([
		_target(12, 2, Vector2(13.0, 0.0)),
		_target(10, 2, Vector2(5.0, 0.0)),
		_target(13, 2, Vector2(20.0, 0.0)),
		_target(11, 2, Vector2(9.0, 0.0)),
	], [request])

	_assert_true(result.is_success(), "Chain must recover from a missing primary target.")
	_assert_equal(_hit_targets(result), [10, 11, 12], "Chain order or exclusion is wrong.")
	_assert_equal(_hit_ordinals(result), [0, 1, 2], "Chain ordinals are wrong.")


func _test_projectiles_sweep_and_choose_earliest_contact() -> void:
	var world := _world()
	var projectile := _projectile_definition(
		"delivery.projectile.fast",
		600.0,
		1.0,
		4,
		1
	)
	var spawn: RefCounted = world.advance_tick(
		[],
		[_request(1, projectile, Vector2.ZERO, Vector2.RIGHT)]
	)
	_assert_true(spawn.is_success(), "Projectile spawn must succeed.")
	_assert_equal(spawn.hits().size(), 0, "Projectiles must not move on their spawn tick.")
	_assert_equal(spawn.spawned_runtime_ids(), [1], "Projectile runtime ID is wrong.")

	var impact: RefCounted = world.advance_tick([
		_target(5, 2, Vector2(7.0, 0.0)),
		_target(3, 2, Vector2(5.0, -1.0)),
		_target(2, 2, Vector2(5.0, 1.0)),
	], [])
	_assert_true(impact.is_success(), "Projectile advance must succeed.")
	_assert_equal(_hit_targets(impact), [2], "Projectile contact ordering is wrong.")
	_assert_equal(impact.expired_runtime_ids(), [1], "Exhausted projectile must expire.")
	_assert_equal(impact.active_count(), 0, "Exhausted projectile remained active.")


func _test_projectile_lifetime_is_exact() -> void:
	var world := _world()
	var projectile := _projectile_definition(
		"delivery.projectile.short",
		60.0,
		0.0,
		1,
		1
	)
	world.advance_tick([], [_request(1, projectile, Vector2.ZERO, Vector2.RIGHT)])
	var expiry: RefCounted = world.advance_tick([], [])

	_assert_equal(expiry.expired_runtime_ids(), [1], "One-tick projectile lifetime is wrong.")
	_assert_equal(expiry.active_count(), 0, "Expired projectile remained active.")


func _test_persistent_pulses_and_expiry_are_exact() -> void:
	var world := _world()
	var persistent := _persistent_definition(
		"delivery.persistent.totem",
		5.0,
		3,
		2,
		0
	)
	var targets := [_target(2, 2, Vector2(5.0, 0.0))]
	var spawn: RefCounted = world.advance_tick(
		targets,
		[_request(1, persistent, Vector2.ZERO)]
	)
	var quiet: RefCounted = world.advance_tick(targets, [])
	var second_pulse: RefCounted = world.advance_tick(targets, [])
	var expiry: RefCounted = world.advance_tick(targets, [])

	_assert_equal(_hit_targets(spawn), [2], "Persistent must pulse on its spawn tick.")
	_assert_equal(quiet.hits().size(), 0, "Persistent pulsed before its interval.")
	_assert_equal(_hit_targets(second_pulse), [2], "Persistent second pulse tick is wrong.")
	_assert_equal(expiry.expired_runtime_ids(), [1], "Persistent expiry tick is wrong.")
	_assert_equal(expiry.hits().size(), 0, "Persistent pulsed on its exclusive expiry tick.")


func _test_invalid_batches_roll_back_all_state() -> void:
	var world := _world()
	var area := _area_definition("delivery.area.rollback", 5.0, 0)
	var accepted: RefCounted = world.advance_tick([], [_request(1, area, Vector2.ZERO)])
	_assert_true(accepted.is_success(), "Setup request must succeed.")
	var before_hash: String = world.state_hash()

	var duplicate: RefCounted = world.advance_tick([], [_request(1, area, Vector2.ZERO)])
	_assert_true(not duplicate.is_success(), "Repeated request IDs must fail.")
	_assert_equal(world.tick(), 1, "Rejected request advanced the tick.")
	_assert_equal(world.state_hash(), before_hash, "Rejected request changed state.")

	var invalid_targets: RefCounted = world.advance_tick([
		_target(2, 2, Vector2.ZERO),
		_target(2, 2, Vector2.ONE),
	], [_request(2, area, Vector2.ZERO)])
	_assert_true(not invalid_targets.is_success(), "Duplicate target IDs must fail.")
	_assert_equal(world.state_hash(), before_hash, "Invalid targets changed state.")


func _test_input_order_does_not_change_results_or_hashes() -> void:
	var left := _world()
	var right := _world()
	var area := _area_definition("delivery.area.order", 20.0, 0)
	var targets := [
		_target(4, 2, Vector2(4.0, 0.0)),
		_target(2, 2, Vector2(2.0, 0.0)),
		_target(3, 2, Vector2(3.0, 0.0)),
	]
	var requests := [
		_request(2, area, Vector2(1.0, 0.0)),
		_request(1, area, Vector2.ZERO),
	]
	var left_result: RefCounted = left.advance_tick(targets, requests)
	var reversed_targets := targets.duplicate()
	reversed_targets.reverse()
	var reversed_requests := requests.duplicate()
	reversed_requests.reverse()
	var right_result: RefCounted = right.advance_tick(reversed_targets, reversed_requests)

	_assert_equal(_hit_keys(left_result), _hit_keys(right_result), "Input order changed hits.")
	_assert_equal(left.state_hash(), right.state_hash(), "Input order changed state hash.")
	_assert_equal(
		left.state_hash(),
		"a878da26c9f06d7f2ec99e9078b33561a11619678fcff5726a8f7a4e452c56ef",
		"Delivery state hash contract changed."
	)


func _test_density_path_uses_compact_values() -> void:
	var world := _world()
	var targets: Array = []
	for runtime_id in range(2, 122):
		targets.append(_target(runtime_id, 2, Vector2(float(runtime_id), 0.0)))
	var area := _area_definition("delivery.area.density", 200.0, 0)
	var result: RefCounted = world.advance_tick(
		targets,
		[_request(1, area, Vector2.ZERO)]
	)

	_assert_true(result.is_success(), "Density request must succeed.")
	_assert_equal(result.hits().size(), 120, "Density request missed targets.")
	_assert_true(not targets[0] is Node, "Delivery targets must not allocate Nodes.")
	var active_values: Array = world.active_values()
	active_values.append(["mutated"])
	_assert_equal(world.active_values(), [], "Published active values leaked mutation.")


func _world() -> RefCounted:
	var world := DeliveryWorld.new()
	_assert_equal(world.configure(0, 1), "", "Delivery world must configure.")
	return world


func _target(
	runtime_id: int,
	team_id: int,
	position: Vector2,
	radius: float = 0.0,
	is_alive: bool = true
) -> RefCounted:
	var target := DeliveryTarget.new()
	_assert_equal(
		target.configure(runtime_id, team_id, position, radius, is_alive),
		"",
		"Delivery target must configure."
	)
	return target


func _request(
	request_id: int,
	definition: RefCounted,
	origin: Vector2,
	direction: Vector2 = Vector2.ZERO,
	primary_target_id: int = 0
) -> RefCounted:
	var request := DeliveryRequest.new()
	_assert_equal(
		request.configure(
			request_id,
			definition,
			1,
			1,
			origin,
			direction,
			primary_target_id
		),
		"",
		"Delivery request must configure."
	)
	return request


func _projectile_definition(
	definition_id: String,
	speed: float,
	radius: float,
	lifetime_ticks: int,
	max_targets: int
) -> RefCounted:
	var definition := DeliveryDefinition.new()
	_assert_equal(
		definition.configure_projectile(
			definition_id,
			radius,
			speed,
			lifetime_ticks,
			max_targets
		),
		"",
		"Projectile definition must configure."
	)
	return definition


func _area_definition(definition_id: String, radius: float, max_targets: int) -> RefCounted:
	var definition := DeliveryDefinition.new()
	_assert_equal(
		definition.configure_area(definition_id, radius, max_targets),
		"",
		"Area definition must configure."
	)
	return definition


func _chain_definition(
	definition_id: String,
	acquisition_range: float,
	jump_range: float,
	max_targets: int
) -> RefCounted:
	var definition := DeliveryDefinition.new()
	_assert_equal(
		definition.configure_chain(
			definition_id,
			acquisition_range,
			jump_range,
			max_targets
		),
		"",
		"Chain definition must configure."
	)
	return definition


func _persistent_definition(
	definition_id: String,
	radius: float,
	lifetime_ticks: int,
	pulse_interval_ticks: int,
	max_targets: int
) -> RefCounted:
	var definition := DeliveryDefinition.new()
	_assert_equal(
		definition.configure_persistent(
			definition_id,
			radius,
			lifetime_ticks,
			pulse_interval_ticks,
			max_targets
		),
		"",
		"Persistent definition must configure."
	)
	return definition


func _hit_targets(result: RefCounted) -> Array:
	var values: Array = []
	for hit: RefCounted in result.hits():
		values.append(hit.target_entity_id())
	return values


func _hit_ordinals(result: RefCounted) -> Array:
	var values: Array = []
	for hit: RefCounted in result.hits():
		values.append(hit.ordinal())
	return values


func _hit_keys(result: RefCounted) -> Array:
	var values: Array = []
	for hit: RefCounted in result.hits():
		values.append([hit.request_id(), hit.target_entity_id(), hit.ordinal()])
	return values


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
