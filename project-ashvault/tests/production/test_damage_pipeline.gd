extends SceneTree

const DamageComponent = preload("res://game/simulation/combat/damage_component.gd")
const DamageContext = preload("res://game/simulation/combat/damage_context.gd")
const DamageModifier = preload("res://game/simulation/combat/damage_modifier.gd")
const DamagePipeline = preload("res://game/simulation/combat/damage_pipeline.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_context_is_validated_and_immutable()
	_test_all_stages_resolve_in_contract_order()
	_test_conversion_is_stable_bounded_and_non_cascading()
	_test_critical_resistance_and_penetration_boundaries()
	_test_negative_damage_and_single_commit_rounding()
	_test_invalid_resolution_has_no_partial_result()
	_test_result_breakdown_is_immutable()

	if failures.is_empty():
		print("Production damage pipeline tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_context_is_validated_and_immutable() -> void:
	var invalid := DamageContext.new()
	_assert_contains(
		invalid.configure(
			0,
			2,
			"ability.arc_bolt",
			3,
			PackedStringArray(),
			[_component("damage.lightning", 10.0, "ability.arc_bolt")],
			[],
			PackedStringArray(),
			0.0,
			1.5,
			0.5
		),
		"positive",
		"Runtime entity IDs must be positive."
	)
	var excessive_critical := DamageContext.new()
	_assert_contains(
		excessive_critical.configure(
			1,
			2,
			"ability.arc_bolt",
			3,
			PackedStringArray(),
			[_component("damage.lightning", 10.0, "ability.arc_bolt")],
			[],
			PackedStringArray(),
			0.951,
			1.5,
			0.5
		),
		"between 0 and 0.95",
		"Critical chance must retain the inherited cap."
	)

	var duplicate := DamageContext.new()
	var modifier := _modifier(
		"damage.physical",
		DamageModifier.Operation.FLAT,
		0.95,
		"source.flat"
	)
	_assert_contains(
		duplicate.configure(
			1,
			2,
			"ability.arc_bolt",
			3,
			PackedStringArray(),
			[_component("damage.physical", 10.0, "ability.arc_bolt")],
			[modifier, modifier],
			PackedStringArray(),
			0.0,
			1.5,
			0.5
		),
		"Duplicate damage modifier",
		"Duplicate modifier identities must be rejected transactionally."
	)

	var context := _context(
		[_component("damage.lightning", 10.0, "ability.arc_bolt")],
		[],
		0.2,
		1.6,
		0.1,
		PackedStringArray(["condition.close_range"]),
		PackedStringArray(["delivery.projectile", "damage.lightning"])
	)
	_assert_equal(
		context.tags(),
		PackedStringArray(["damage.lightning", "delivery.projectile"]),
		"Context tags must publish in stable order."
	)
	_assert_contains(
		context.configure(
			1, 2, "ability.changed", 3, PackedStringArray(), [], [],
			PackedStringArray(), 0.0, 1.0, 0.0
		),
		"immutable",
		"Configured contexts must reject mutation."
	)
	_assert_equal(context.ability_id(), "ability.arc_bolt", "Rejected mutation changed context.")


func _test_all_stages_resolve_in_contract_order() -> void:
	_assert_equal(
		DamagePipeline.STAGE_NAMES,
		[
			"BASE_FLAT",
			"INCREASED",
			"MORE",
			"CONVERSION",
			"CRITICAL",
			"DEFENSE",
			"RESISTANCE_PENETRATION",
			"CONDITIONAL",
			"FINAL_CLAMP",
		],
		"Damage stage ordinals are a simulation compatibility contract."
	)
	var context := _context(
		[
			_component("damage.physical", 100.0, "ability.arc_bolt"),
			_component("damage.fire", 20.0, "source.ember"),
		],
		[
			_modifier("damage.physical", DamageModifier.Operation.FLAT, 20.0, "source.flat"),
			_modifier("damage.fire", DamageModifier.Operation.FLAT, 10.0, "source.fire_flat"),
			_modifier("damage.physical", DamageModifier.Operation.INCREASED, 0.5, "source.increased"),
			_modifier("damage.physical", DamageModifier.Operation.MORE, 0.25, "source.more"),
			_modifier(
				"damage.physical",
				DamageModifier.Operation.CONVERSION,
				0.4,
				"source.conversion",
				"damage.lightning"
			),
			_modifier("damage.physical", DamageModifier.Operation.DEFENSE, 100.0, "source.armor"),
			_modifier("damage.physical", DamageModifier.Operation.RESISTANCE, 0.2, "source.physical_resistance"),
			_modifier("damage.physical", DamageModifier.Operation.PENETRATION, 0.05, "source.physical_penetration"),
			_modifier("damage.lightning", DamageModifier.Operation.RESISTANCE, 0.25, "source.lightning_resistance"),
			_modifier("damage.lightning", DamageModifier.Operation.PENETRATION, 0.5, "source.lightning_penetration"),
			_modifier(
				"damage.lightning",
				DamageModifier.Operation.CONDITIONAL,
				0.1,
				"source.close_range",
				"",
				"condition.close_range"
			),
		],
		0.95,
		2.0,
		0.0,
		PackedStringArray(["condition.close_range"])
	)
	var resolution: RefCounted = DamagePipeline.resolve(context)
	_assert_equal(resolution.errors(), PackedStringArray(), "Valid damage must resolve.")
	var result: RefCounted = resolution.result()

	_assert_true(result.is_critical(), "A zero roll must critically hit at the chance cap.")
	_assert_float(result.total_damage(), 422.25, "Damage stages resolved in the wrong order.")
	_assert_equal(result.committed_amount(), 422, "Committed damage must round the final total once.")
	_assert_float(result.mitigated_amount(), 110.25, "Mitigation total is incorrect.")
	var physical := _breakdown_for(result, "damage.physical")
	_assert_float(physical["base_flat"], 120.0, "Base and flat stage is wrong.")
	_assert_float(physical["increased"], 180.0, "Increased stage is wrong.")
	_assert_float(physical["more"], 225.0, "More stage is wrong.")
	_assert_float(physical["conversion"], 135.0, "Conversion source stage is wrong.")
	_assert_float(physical["critical"], 270.0, "Critical stage is wrong.")
	_assert_float(physical["defense"], 135.0, "Defense stage is wrong.")
	_assert_float(physical["resistance_penetration"], 114.75, "Resistance stage is wrong.")
	var lightning := _breakdown_for(result, "damage.lightning")
	_assert_float(lightning["conversion"], 90.0, "Converted damage is wrong.")
	_assert_float(lightning["resistance_penetration"], 225.0, "Penetration must permit vulnerability.")
	_assert_float(lightning["conditional"], 247.5, "Conditional stage is wrong.")
	_assert_true(
		result.contributing_source_ids().has("source.armor"),
		"Mitigation sources must be retained."
	)
	var physical_mitigation := _mitigation_for(result, "damage.physical")
	_assert_equal(
		physical_mitigation["defense_sources"],
		PackedStringArray(["source.armor"]),
		"Mitigation breakdown must identify defense sources."
	)
	_assert_float(
		physical_mitigation["effective_resistance"],
		0.15,
		"Mitigation breakdown must expose effective resistance."
	)
	var armor_source := _source_for(result, "source.armor")
	_assert_equal(armor_source["operation"], "DEFENSE", "Source breakdown lost its operation.")
	_assert_true(armor_source["applied"], "Source breakdown must identify applied sources.")


func _test_conversion_is_stable_bounded_and_non_cascading() -> void:
	var alpha := _modifier(
		"damage.physical", DamageModifier.Operation.CONVERSION, 0.75,
		"source.alpha", "damage.cold", "", 10
	)
	var beta := _modifier(
		"damage.physical", DamageModifier.Operation.CONVERSION, 0.75,
		"source.beta", "damage.fire", "", 10
	)
	var no_cascade := _modifier(
		"damage.cold", DamageModifier.Operation.CONVERSION, 1.0,
		"source.gamma", "damage.fire", "", 20
	)
	var base := [_component("damage.physical", 100.0, "ability.arc_bolt")]
	var first: RefCounted = DamagePipeline.resolve(
		_context(base, [beta, no_cascade, alpha])
	).result()
	var second: RefCounted = DamagePipeline.resolve(
		_context(base, [alpha, beta, no_cascade])
	).result()

	_assert_equal(first.component_breakdown(), second.component_breakdown(), "Modifier input order changed conversion.")
	_assert_float(_breakdown_for(first, "damage.physical")["conversion"], 0.0, "Conversion must cap at 100%.")
	_assert_float(_breakdown_for(first, "damage.cold")["conversion"], 75.0, "Lexical source order must win ties.")
	_assert_float(_breakdown_for(first, "damage.fire")["conversion"], 25.0, "Remaining allocation is wrong.")


func _test_critical_resistance_and_penetration_boundaries() -> void:
	var base := [_component("damage.lightning", 100.0, "ability.arc_bolt")]
	var defenses := [
		_modifier("damage.lightning", DamageModifier.Operation.RESISTANCE, 2.0, "source.resistance"),
	]
	var critical: RefCounted = DamagePipeline.resolve(
		_context(base, defenses, 0.95, 2.0, 0.949999)
	).result()
	var normal: RefCounted = DamagePipeline.resolve(
		_context(base, defenses, 0.95, 2.0, 0.95)
	).result()
	_assert_float(critical.total_damage(), 30.0, "Critical and maximum resistance boundaries are wrong.")
	_assert_float(normal.total_damage(), 15.0, "Critical comparison must be strict less-than.")

	var vulnerable: RefCounted = DamagePipeline.resolve(
		_context(base, [
			_modifier("damage.lightning", DamageModifier.Operation.RESISTANCE, 0.2, "source.resistance"),
			_modifier("damage.lightning", DamageModifier.Operation.PENETRATION, 4.0, "source.penetration"),
		])
	).result()
	_assert_float(vulnerable.total_damage(), 200.0, "Effective resistance must clamp at -100%.")


func _test_negative_damage_and_single_commit_rounding() -> void:
	var negative: RefCounted = DamagePipeline.resolve(_context(
		[_component("damage.physical", 1.0, "ability.arc_bolt")],
		[_modifier("damage.physical", DamageModifier.Operation.FLAT, -10.0, "source.penalty")]
	)).result()
	_assert_float(negative.total_damage(), 0.0, "Negative final damage must clamp to zero.")
	_assert_equal(negative.committed_amount(), 0, "Negative damage must not become healing.")

	var split: RefCounted = DamagePipeline.resolve(_context([
		_component("damage.fire", 0.6, "source.fire"),
		_component("damage.cold", 0.6, "source.cold"),
	])).result()
	_assert_float(split.total_damage(), 1.2, "Fractional components must remain floating point.")
	_assert_equal(split.committed_amount(), 1, "Components must not be rounded individually.")


func _test_invalid_resolution_has_no_partial_result() -> void:
	var resolution: RefCounted = DamagePipeline.resolve(null)
	_assert_true(not resolution.is_success(), "Invalid input must fail resolution.")
	_assert_true(resolution.result() == null, "Invalid input must not publish a partial result.")
	_assert_contains(resolution.errors(), "configured DamageContext", "Invalid input must be diagnosed.")


func _test_result_breakdown_is_immutable() -> void:
	var result: RefCounted = DamagePipeline.resolve(_context([
		_component("damage.lightning", 10.0, "ability.arc_bolt")
	])).result()
	var leaked: Array = result.component_breakdown()
	leaked[0]["final"] = 999.0
	leaked.append({"damage_type_id": "damage.void"})
	_assert_float(result.total_damage(), 10.0, "Caller mutation changed total damage.")
	_assert_float(
		_breakdown_for(result, "damage.lightning")["final"],
		10.0,
		"Caller mutation changed the published breakdown."
	)


func _context(
	components: Array,
	modifiers: Array = [],
	critical_chance: float = 0.0,
	critical_multiplier: float = 1.5,
	critical_roll: float = 0.5,
	active_conditions: PackedStringArray = PackedStringArray(),
	tags: PackedStringArray = PackedStringArray(["event.hit"])
) -> RefCounted:
	var context := DamageContext.new()
	var error: String = context.configure(
		1,
		2,
		"ability.arc_bolt",
		3,
		tags,
		components,
		modifiers,
		active_conditions,
		critical_chance,
		critical_multiplier,
		critical_roll
	)
	assert(error.is_empty(), error)
	return context


func _component(damage_type_id: String, amount: float, source_id: String) -> RefCounted:
	var component := DamageComponent.new()
	var error: String = component.configure(damage_type_id, amount, source_id)
	assert(error.is_empty(), error)
	return component


func _modifier(
	damage_type_id: String,
	operation: int,
	value: float,
	source_id: String,
	target_damage_type_id: String = "",
	condition_id: String = "",
	priority: int = 0
) -> RefCounted:
	var modifier := DamageModifier.new()
	var error: String = modifier.configure(
		damage_type_id,
		operation,
		value,
		source_id,
		target_damage_type_id,
		condition_id,
		priority
	)
	assert(error.is_empty(), error)
	return modifier


func _breakdown_for(result: RefCounted, damage_type_id: String) -> Dictionary:
	for component: Dictionary in result.component_breakdown():
		if component["damage_type_id"] == damage_type_id:
			return component
	return {}


func _mitigation_for(result: RefCounted, damage_type_id: String) -> Dictionary:
	for mitigation: Dictionary in result.mitigation_breakdown():
		if mitigation["damage_type_id"] == damage_type_id:
			return mitigation
	return {}


func _source_for(result: RefCounted, source_id: String) -> Dictionary:
	for source: Dictionary in result.source_breakdown():
		if source["source_id"] == source_id:
			return source
	return {}


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
