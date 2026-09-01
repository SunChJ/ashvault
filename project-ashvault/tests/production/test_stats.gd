extends SceneTree

const StatDefinition = preload("res://game/simulation/stats/stat_definition.gd")
const StatModifier = preload("res://game/simulation/stats/stat_modifier.gd")
const StatRegistry = preload("res://game/simulation/stats/stat_registry.gd")
const StatResolver = preload("res://game/simulation/stats/stat_resolver.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_publication_is_transactional()
	_test_modifier_configuration_contract()
	_test_all_operations_resolve_in_contract_order()
	_test_conversion_conflicts_are_stable_and_non_cascading()
	_test_conditions_and_override_precedence_are_explainable()
	_test_invalid_resolution_has_no_partial_snapshot()
	_test_snapshots_do_not_expose_mutable_storage()

	if failures.is_empty():
		print("Production stat system tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_registry_publication_is_transactional() -> void:
	var duplicate_registry := StatRegistry.new()
	var duplicate_errors := duplicate_registry.load_definitions([
		_definition("stat.damage", 100.0),
		_definition("stat.damage", 200.0),
	])
	_assert_contains(duplicate_errors, "Duplicate stat ID", "Duplicate stats must fail.")
	_assert_true(
		not duplicate_registry.is_loaded(),
		"Rejected registry publication must not expose partial state."
	)

	var invalid_definition := StatDefinition.new()
	_assert_true(
		invalid_definition.configure("Damage", 1.0).contains("Invalid stable ID"),
		"Stat IDs must use the stable ID contract."
	)
	_assert_true(
		StatDefinition.new().configure("stat.invalid", NAN).contains("finite"),
		"Default stat values must be finite."
	)

	var registry := _registry([
		_definition("stat.speed", 1.0),
		_definition("stat.damage", 100.0),
	])
	_assert_equal(
		registry.ids(),
		PackedStringArray(["stat.damage", "stat.speed"]),
		"Published stat IDs must be stable and sorted."
	)
	_assert_float(
		registry.get_definition("stat.damage").default_value(),
		100.0,
		"Registry lookups must retain default values."
	)


func _test_modifier_configuration_contract() -> void:
	var missing_target := StatModifier.new()
	_assert_true(
		missing_target.configure(
			"damage.physical",
			StatModifier.Operation.CONVERSION,
			0.5,
			"source.conversion"
		).contains("Conversion target"),
		"Conversions must require a stable target stat."
	)
	var excessive_conversion := StatModifier.new()
	_assert_true(
		excessive_conversion.configure(
			"damage.physical",
			StatModifier.Operation.CONVERSION,
			1.01,
			"source.conversion",
			"",
			0,
			"damage.cold"
		).contains("between 0 and 1"),
		"Individual conversion requests must be bounded."
	)
	var unexpected_target := StatModifier.new()
	_assert_true(
		unexpected_target.configure(
			"stat.power",
			StatModifier.Operation.FLAT,
			1.0,
			"source.flat",
			"",
			0,
			"stat.guard"
		).contains("Only CONVERSION"),
		"Non-conversion modifiers must not define targets."
	)
	var immutable := _modifier(
		"stat.power",
		StatModifier.Operation.FLAT,
		10.0,
		"source.immutable"
	)
	_assert_true(
		immutable.configure(
			"stat.power",
			StatModifier.Operation.FLAT,
			20.0,
			"source.changed"
		).contains("immutable"),
		"Configured modifiers must reject mutation."
	)
	_assert_float(immutable.amount(), 10.0, "Rejected mutation must retain the value.")


func _test_all_operations_resolve_in_contract_order() -> void:
	_assert_equal(
		StatModifier.OPERATION_NAMES,
		["BASE", "FLAT", "INCREASED", "MORE", "CONVERSION", "OVERRIDE", "CAP"],
		"Modifier operation ordinals are a simulation compatibility contract."
	)
	var registry := _registry([
		_definition("stat.power", 100.0),
		_definition("damage.physical", 100.0),
		_definition("damage.cold", 10.0),
		_definition("stat.guard", 100.0),
	])
	var modifiers: Array = [
		_modifier("stat.power", StatModifier.Operation.BASE, 20.0, "source.base"),
		_modifier("stat.power", StatModifier.Operation.FLAT, 30.0, "source.flat"),
		_modifier("stat.power", StatModifier.Operation.INCREASED, 0.5, "source.increased"),
		_modifier("stat.power", StatModifier.Operation.MORE, 0.2, "source.more"),
		_modifier(
			"damage.physical",
			StatModifier.Operation.CONVERSION,
			0.5,
			"source.conversion",
			"",
			0,
			"damage.cold"
		),
		_modifier("stat.guard", StatModifier.Operation.OVERRIDE, 300.0, "source.override"),
		_modifier("stat.guard", StatModifier.Operation.CAP, 275.0, "source.cap_high", "", 10),
		_modifier("stat.guard", StatModifier.Operation.CAP, 250.0, "source.cap_low"),
	]
	var result := StatResolver.resolve(registry, modifiers, PackedStringArray(), 17)

	_assert_equal(result.errors(), PackedStringArray(), "Valid modifiers must resolve.")
	var snapshot: RefCounted = result.snapshot()
	_assert_equal(snapshot.tick(), 17, "Snapshots must retain their simulation tick.")
	_assert_float(snapshot.value("stat.power"), 270.0, "BASE/FLAT/INCREASED/MORE order is wrong.")
	_assert_float(snapshot.value("damage.physical"), 50.0, "Conversion must subtract from its source.")
	_assert_float(snapshot.value("damage.cold"), 60.0, "Conversion must add after target MORE stage.")
	_assert_float(snapshot.value("stat.guard"), 250.0, "CAP must apply after OVERRIDE.")
	_assert_equal(
		_applied_operations(snapshot.explanation("stat.power")),
		["BASE", "FLAT", "INCREASED", "MORE"],
		"Explanations must retain stage order."
	)


func _test_conversion_conflicts_are_stable_and_non_cascading() -> void:
	var registry := _registry([
		_definition("damage.physical", 100.0),
		_definition("damage.cold", 0.0),
		_definition("damage.fire", 0.0),
	])
	var alpha := _modifier(
		"damage.physical",
		StatModifier.Operation.CONVERSION,
		0.75,
		"source.alpha",
		"",
		10,
		"damage.cold"
	)
	var beta := _modifier(
		"damage.physical",
		StatModifier.Operation.CONVERSION,
		0.75,
		"source.beta",
		"",
		10,
		"damage.fire"
	)
	var no_cascade := _modifier(
		"damage.cold",
		StatModifier.Operation.CONVERSION,
		1.0,
		"source.gamma",
		"",
		20,
		"damage.fire"
	)
	var first: RefCounted = StatResolver.resolve(
		registry,
		[beta, no_cascade, alpha],
		PackedStringArray(),
		1
	).snapshot()
	var second: RefCounted = StatResolver.resolve(
		registry,
		[alpha, beta, no_cascade],
		PackedStringArray(),
		1
	).snapshot()

	_assert_equal(first.values(), second.values(), "Modifier input order must not change values.")
	_assert_equal(
		first.explanation("damage.physical"),
		second.explanation("damage.physical"),
		"Modifier input order must not change provenance."
	)
	_assert_float(first.value("damage.physical"), 0.0, "Conversion allocation must cap at 100%.")
	_assert_float(first.value("damage.cold"), 75.0, "Lexical source order must win equal priority.")
	_assert_float(first.value("damage.fire"), 25.0, "Lower precedence conversion must use remaining allocation.")
	var conversions: Array = first.explanation("damage.physical")["applied_sources"]
	_assert_float(conversions[0]["applied_fraction"], 0.75, "First conversion allocation is wrong.")
	_assert_float(conversions[1]["applied_fraction"], 0.25, "Second conversion must be normalized.")

	var priority_winner := _modifier(
		"damage.physical",
		StatModifier.Operation.CONVERSION,
		0.6,
		"source.zeta",
		"",
		20,
		"damage.fire"
	)
	var priority_snapshot: RefCounted = StatResolver.resolve(
		registry,
		[alpha, priority_winner],
		PackedStringArray(),
		1
	).snapshot()
	_assert_float(
		priority_snapshot.value("damage.fire"),
		60.0,
		"Higher numeric priority must reserve conversion allocation first."
	)
	_assert_float(
		priority_snapshot.value("damage.cold"),
		40.0,
		"Lower priority conversion must receive only remaining allocation."
	)


func _test_conditions_and_override_precedence_are_explainable() -> void:
	var registry := _registry([_definition("stat.power", 100.0)])
	var modifiers: Array = [
		_modifier(
			"stat.power",
			StatModifier.Operation.FLAT,
			25.0,
			"source.active",
			"condition.empowered"
		),
		_modifier(
			"stat.power",
			StatModifier.Operation.MORE,
			1.0,
			"source.inactive",
			"condition.low_health"
		),
		_modifier("stat.power", StatModifier.Operation.OVERRIDE, 200.0, "source.alpha", "", 10),
		_modifier("stat.power", StatModifier.Operation.OVERRIDE, 300.0, "source.beta", "", 10),
	]
	var snapshot: RefCounted = StatResolver.resolve(
		registry,
		modifiers,
		PackedStringArray(["condition.empowered"]),
		2
	).snapshot()

	_assert_float(snapshot.value("stat.power"), 200.0, "Stable source ordering must select the override winner.")
	var explanation: Dictionary = snapshot.explanation("stat.power")
	_assert_equal(
		_find_source(explanation["applied_sources"], "source.active")["condition_id"],
		"condition.empowered",
		"Applied conditional sources must remain explainable."
	)
	_assert_equal(
		_find_source(explanation["skipped_sources"], "source.inactive")["reason"],
		"inactive_condition",
		"Inactive conditional sources must retain their reason."
	)
	_assert_equal(
		_find_source(explanation["skipped_sources"], "source.beta")["reason"],
		"lower_precedence_override",
		"Shadowed overrides must retain their reason."
	)


func _test_invalid_resolution_has_no_partial_snapshot() -> void:
	var registry := _registry([
		_definition("stat.power", 100.0),
		_definition("damage.physical", 100.0),
	])
	var duplicate := _modifier("stat.power", StatModifier.Operation.FLAT, 10.0, "source.same")
	var duplicate_again := _modifier("stat.power", StatModifier.Operation.FLAT, 20.0, "source.same")
	var unknown := _modifier("stat.missing", StatModifier.Operation.FLAT, 1.0, "source.unknown")
	var bad_conversion := _modifier(
		"damage.physical",
		StatModifier.Operation.CONVERSION,
		0.5,
		"source.bad_conversion",
		"",
		0,
		"damage.void"
	)
	var result := StatResolver.resolve(
		registry,
		[duplicate, duplicate_again, unknown, bad_conversion],
		PackedStringArray(["Invalid Condition"]),
		3
	)

	_assert_true(not result.is_success(), "Invalid modifiers must fail resolution.")
	_assert_true(result.snapshot() == null, "Failed resolution must not publish a snapshot.")
	_assert_contains(result.errors(), "Duplicate modifier", "Duplicate sources must be diagnosed.")
	_assert_contains(result.errors(), "Unknown stat ID", "Unknown stats must be diagnosed.")
	_assert_contains(result.errors(), "Unknown conversion target", "Unknown targets must be diagnosed.")
	_assert_contains(result.errors(), "Invalid active condition", "Condition IDs must be validated.")

	var overflow_registry := _registry([_definition("stat.overflow", 1.0e308)])
	var overflow_modifier := _modifier(
		"stat.overflow",
		StatModifier.Operation.MORE,
		1.0e308,
		"source.overflow"
	)
	var overflow_result := StatResolver.resolve(
		overflow_registry,
		[overflow_modifier],
		PackedStringArray(),
		3
	)
	_assert_true(
		overflow_result.snapshot() == null,
		"Non-finite calculations must not publish a snapshot."
	)
	_assert_contains(
		overflow_result.errors(),
		"not finite",
		"Non-finite calculations must be diagnosed."
	)


func _test_snapshots_do_not_expose_mutable_storage() -> void:
	var registry := _registry([_definition("stat.power", 100.0)])
	var modifier := _modifier("stat.power", StatModifier.Operation.FLAT, 25.0, "source.flat")
	var snapshot: RefCounted = StatResolver.resolve(
		registry,
		[modifier],
		PackedStringArray(),
		99
	).snapshot()

	var leaked_values: Dictionary = snapshot.values()
	leaked_values["stat.power"] = -1.0
	var leaked_explanation: Dictionary = snapshot.explanation("stat.power")
	leaked_explanation["final_value"] = -1.0
	leaked_explanation["applied_sources"][0]["source_id"] = "source.changed"
	var reconfigure_error: String = snapshot._configure(100, {}, {})

	_assert_float(snapshot.value("stat.power"), 125.0, "Returned values must be copies.")
	_assert_true(
		reconfigure_error.contains("immutable"),
		"Published snapshots must reject reconfiguration."
	)
	_assert_equal(snapshot.tick(), 99, "Rejected reconfiguration must retain the tick.")
	_assert_equal(
		snapshot.explanation("stat.power")["applied_sources"][0]["source_id"],
		"source.flat",
		"Returned explanations must be deep copies."
	)


func _definition(stat_id: String, default_value: float) -> RefCounted:
	var definition := StatDefinition.new()
	var error := definition.configure(stat_id, default_value)
	_assert_equal(error, "", "Synthetic stat definition must configure.")
	return definition


func _registry(definitions: Array) -> RefCounted:
	var registry := StatRegistry.new()
	var errors := registry.load_definitions(definitions)
	_assert_equal(errors, PackedStringArray(), "Synthetic stat registry must publish.")
	return registry


func _modifier(
	stat_id: String,
	operation: int,
	value: float,
	source_id: String,
	condition_id: String = "",
	priority: int = 0,
	target_stat_id: String = ""
) -> RefCounted:
	var modifier := StatModifier.new()
	var error := modifier.configure(
		stat_id,
		operation,
		value,
		source_id,
		condition_id,
		priority,
		target_stat_id
	)
	_assert_equal(error, "", "Synthetic modifier must configure.")
	return modifier


func _applied_operations(explanation: Dictionary) -> Array[String]:
	var operations: Array[String] = []
	for source: Dictionary in explanation["applied_sources"]:
		operations.append(source["operation"])
	return operations


func _find_source(sources: Array, source_id: String) -> Dictionary:
	for source: Dictionary in sources:
		if source["source_id"] == source_id:
			return source
	failures.append("Missing source '%s' in explanation." % source_id)
	return {}


func _assert_contains(values: PackedStringArray, needle: String, message: String) -> void:
	for value in values:
		if value.contains(needle):
			return
	failures.append("%s Missing '%s' in %s." % [message, needle, values])


func _assert_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
