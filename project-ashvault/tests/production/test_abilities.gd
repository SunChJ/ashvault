extends SceneTree

const AbilityDamageComponent = preload(
	"res://game/simulation/abilities/ability_damage_component.gd"
)
const AbilityDamageModifier = preload(
	"res://game/simulation/abilities/ability_damage_modifier.gd"
)
const AbilityDefinition = preload(
	"res://game/simulation/abilities/ability_definition.gd"
)
const AbilityEffectDefinition = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const AbilityEffectTransform = preload(
	"res://game/simulation/abilities/ability_effect_transform.gd"
)
const AbilityExecutionContext = preload(
	"res://game/simulation/abilities/ability_execution_context.gd"
)
const AbilityExecutor = preload(
	"res://game/simulation/abilities/ability_executor.gd"
)
const AbilityRankMilestone = preload(
	"res://game/simulation/abilities/ability_rank_milestone.gd"
)
const DamageModifier = preload("res://game/simulation/combat/damage_modifier.gd")
const StatDefinition = preload("res://game/simulation/stats/stat_definition.gd")
const StatRegistry = preload("res://game/simulation/stats/stat_registry.gd")
const StatResolver = preload("res://game/simulation/stats/stat_resolver.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definition_expresses_the_full_contract()
	_test_synthetic_ability_executes_all_effect_kinds()
	_test_invalid_effect_graphs_are_rejected_transactionally()
	_test_rank_milestones_replace_effects_cumulatively()
	_test_invalid_milestone_graph_is_rejected()
	_test_execution_failure_publishes_no_partial_outputs()
	_test_effect_outputs_are_immutable()

	if failures.is_empty():
		print("Production ability tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_definition_expresses_the_full_contract() -> void:
	var ability: RefCounted = _synthetic_ability()
	_assert_equal(ability.content_id, "ability.synthetic.storm_lance", "Ability ID is wrong.")
	_assert_equal(ability.cost_resource_id(), "resource.mana", "Resource cost ID is wrong.")
	_assert_float(ability.cost_amount(), 18.0, "Resource cost amount is wrong.")
	_assert_equal(ability.cooldown_ticks(), 90, "Cooldown ticks are wrong.")
	_assert_equal(ability.cast_time_ticks(), 12, "Cast time ticks are wrong.")
	_assert_equal(ability.recovery_ticks(), 8, "Recovery ticks are wrong.")
	_assert_equal(
		ability.targeting(),
		AbilityDefinition.Targeting.ENTITY,
		"Targeting mode is wrong."
	)
	_assert_equal(
		ability.delivery(),
		AbilityDefinition.Delivery.PROJECTILE,
		"Delivery mode is wrong."
	)
	_assert_equal(
		_effect_ids(ability.effects_for_rank(1)),
		[
			"effect.synthetic.damage",
			"effect.synthetic.status",
			"effect.synthetic.movement",
			"effect.synthetic.projectile",
			"effect.synthetic.persistent",
			"effect.synthetic.event",
		],
		"Ability effects must retain dependency-safe authored order."
	)
	_assert_contains(
		ability.configure_ability(
			"ability.changed", [], [], "", 0.0, 0, 0, 0,
			AbilityDefinition.Targeting.SELF,
			AbilityDefinition.Delivery.INSTANT,
			[], []
		),
		"immutable",
		"Configured abilities must reject mutation."
	)
	_assert_equal(ability.content_id, "ability.synthetic.storm_lance", "Mutation changed ability ID.")


func _test_synthetic_ability_executes_all_effect_kinds() -> void:
	var snapshot := _snapshot({
		"stat.spell_power": 20.0,
		"stat.critical_chance": 0.5,
		"stat.critical_multiplier": 2.0,
	})
	var runtime_conversion := _damage_modifier(
		"damage.lightning",
		DamageModifier.Operation.CONVERSION,
		0.5,
		"source.runtime_conversion",
		"damage.cold"
	)
	var context := _execution_context(snapshot, 1, [runtime_conversion], 0.25)
	var result: RefCounted = AbilityExecutor.execute(_synthetic_ability(), context)

	_assert_true(result.is_success(), "A valid synthetic ability must execute.")
	var outputs: Array = result.outputs()
	_assert_equal(
		_output_kinds(outputs),
		[
			AbilityEffectDefinition.Kind.DAMAGE,
			AbilityEffectDefinition.Kind.STATUS,
			AbilityEffectDefinition.Kind.MOVEMENT,
			AbilityEffectDefinition.Kind.PROJECTILE,
			AbilityEffectDefinition.Kind.PERSISTENT_ENTITY,
			AbilityEffectDefinition.Kind.EVENT,
		],
		"All effect kinds must execute in graph order."
	)
	var damage_result: RefCounted = outputs[0].damage_result()
	_assert_float(damage_result.total_damage(), 90.0, "Damage did not use stats and pipeline once.")
	_assert_true(damage_result.is_critical(), "Critical stats were not consumed.")
	_assert_float(
		_breakdown_for(damage_result, "damage.lightning")["final"],
		45.0,
		"Runtime conversion source amount is wrong."
	)
	_assert_float(
		_breakdown_for(damage_result, "damage.cold")["final"],
		45.0,
		"Runtime conversion target amount is wrong."
	)
	_assert_equal(
		outputs[1].command().effect().status_definition_id(),
		"status.synthetic.shocked",
		"Status command lost its typed definition."
	)
	_assert_equal(
		outputs[2].command().effect().movement_mode_id(),
		"movement.dash",
		"Movement command lost its typed definition."
	)
	_assert_equal(
		outputs[3].command().effect().projectile_definition_id(),
		"projectile.synthetic.storm_lance",
		"Projectile command lost its typed definition."
	)
	_assert_equal(
		outputs[4].command().effect().entity_definition_id(),
		"entity.synthetic.storm_echo",
		"Persistent command lost its typed definition."
	)
	var event_request: RefCounted = outputs[5].event_request()
	_assert_equal(event_request.event_type(), "event.kill", "Event effect type is wrong.")
	_assert_equal(event_request.source_definition_id(), "ability.synthetic.storm_lance", "Event source is wrong.")
	_assert_equal(event_request.payload()["reason"], "synthetic", "Event payload is wrong.")


func _test_invalid_effect_graphs_are_rejected_transactionally() -> void:
	var missing_dependency := _status_effect(
		"effect.invalid.missing",
		PackedStringArray(["effect.invalid.unknown"])
	)
	var missing := AbilityDefinition.new()
	_assert_contains(
		_configure_ability(missing, [missing_dependency]),
		"unknown dependency",
		"Missing effect dependencies must be rejected."
	)
	_assert_true(not missing.is_configured(), "Rejected graphs must not publish an ability.")

	var alpha := _status_effect(
		"effect.invalid.alpha",
		PackedStringArray(["effect.invalid.beta"])
	)
	var beta := _status_effect(
		"effect.invalid.beta",
		PackedStringArray(["effect.invalid.alpha"])
	)
	var cycle := AbilityDefinition.new()
	_assert_contains(
		_configure_ability(cycle, [alpha, beta]),
		"cycle",
		"Effect dependency cycles must be rejected."
	)

	var duplicate := AbilityDefinition.new()
	var same := _status_effect("effect.invalid.duplicate")
	_assert_contains(
		_configure_ability(duplicate, [same, same]),
		"Duplicate effect ID",
		"Duplicate effect IDs must be rejected."
	)


func _test_rank_milestones_replace_effects_cumulatively() -> void:
	var base_damage := _damage_effect("effect.rank.damage", 10.0)
	var rank_three_damage := _damage_effect("effect.rank.damage", 25.0)
	var transform := _transform(
		"milestone.rank_three.damage",
		"effect.rank.damage",
		rank_three_damage
	)
	var milestone := _milestone(3, [transform])
	var ability := AbilityDefinition.new()
	var error: String = ability.configure_ability(
		"ability.synthetic.rank_test",
		["ability.damage"],
		[],
		"",
		0.0,
		0,
		0,
		0,
		AbilityDefinition.Targeting.ENTITY,
		AbilityDefinition.Delivery.INSTANT,
		[base_damage],
		[milestone]
	)
	_assert_equal(error, "", "Valid milestone ability must configure.")
	var snapshot := _snapshot({"stat.placeholder": 0.0})
	var rank_two: RefCounted = AbilityExecutor.execute(
		ability,
		_execution_context(snapshot, 2)
	)
	var rank_three: RefCounted = AbilityExecutor.execute(
		ability,
		_execution_context(snapshot, 3)
	)
	_assert_float(rank_two.outputs()[0].damage_result().total_damage(), 10.0, "Base rank damage is wrong.")
	_assert_float(rank_three.outputs()[0].damage_result().total_damage(), 25.0, "Milestone replacement did not apply.")


func _test_invalid_milestone_graph_is_rejected() -> void:
	var alpha := _status_effect("effect.milestone.alpha")
	var beta := _status_effect(
		"effect.milestone.beta",
		PackedStringArray(["effect.milestone.alpha"])
	)
	var replacement := _status_effect(
		"effect.milestone.alpha",
		PackedStringArray(["effect.milestone.beta"])
	)
	var milestone := _milestone(3, [
		_transform(
			"milestone.invalid.cycle",
			"effect.milestone.alpha",
			replacement
		),
	])
	var ability := AbilityDefinition.new()
	_assert_contains(
		_configure_ability(ability, [alpha, beta], [milestone]),
		"rank 3",
		"Milestones that create invalid graphs must be rejected."
	)

	var unknown_transform := _transform(
		"milestone.invalid.target",
		"effect.milestone.unknown",
		_status_effect("effect.milestone.unknown")
	)
	var unknown := AbilityDefinition.new()
	_assert_contains(
		_configure_ability(unknown, [alpha], [_milestone(2, [unknown_transform])]),
		"unknown target",
		"Milestone transforms must target an existing effect."
	)

	var projectile := AbilityEffectDefinition.new()
	_assert_equal(
		projectile.configure_projectile(
			"effect.milestone.projectile",
			PackedStringArray(),
			PackedStringArray(),
			"projectile.synthetic.validation",
			10.0,
			60
		),
		"",
		"Milestone projectile must configure."
	)
	var removed_delivery := _status_effect("effect.milestone.projectile")
	var delivery_transform := _transform(
		"milestone.invalid.delivery",
		"effect.milestone.projectile",
		removed_delivery
	)
	var invalid_delivery := AbilityDefinition.new()
	_assert_contains(
		invalid_delivery.configure_ability(
			"ability.synthetic.invalid_delivery",
			["ability.validation"],
			[],
			"",
			0.0,
			0,
			0,
			0,
			AbilityDefinition.Targeting.ENTITY,
			AbilityDefinition.Delivery.PROJECTILE,
			[projectile],
			[_milestone(2, [delivery_transform])]
		),
		"rank 2",
		"Milestones must retain delivery-required effect kinds."
	)


func _test_execution_failure_publishes_no_partial_outputs() -> void:
	var status := _status_effect("effect.transaction.status")
	var missing_stat_damage := _damage_effect(
		"effect.transaction.damage",
		10.0,
		"stat.missing"
	)
	var ability := AbilityDefinition.new()
	_assert_equal(
		_configure_ability(ability, [status, missing_stat_damage]),
		"",
		"Synthetic failure ability must configure."
	)
	var result: RefCounted = AbilityExecutor.execute(
		ability,
		_execution_context(_snapshot({"stat.present": 1.0}), 1)
	)
	_assert_true(not result.is_success(), "Missing scaling stats must fail execution.")
	_assert_equal(result.outputs(), [], "Failed execution published partial commands.")
	_assert_contains(result.errors(), "stat.missing", "Execution error must name the missing stat.")


func _test_effect_outputs_are_immutable() -> void:
	var result: RefCounted = AbilityExecutor.execute(
		_synthetic_ability(),
		_execution_context(_snapshot({
			"stat.spell_power": 20.0,
			"stat.critical_chance": 0.0,
			"stat.critical_multiplier": 1.0,
		}), 1)
	)
	var leaked: Array = result.outputs()
	leaked.clear()
	_assert_equal(result.outputs().size(), 6, "Caller mutation changed execution outputs.")


func _synthetic_ability() -> RefCounted:
	var ability := AbilityDefinition.new()
	var damage := _damage_effect("effect.synthetic.damage", 10.0, "stat.spell_power")
	var status := _status_effect(
		"effect.synthetic.status",
		PackedStringArray(["effect.synthetic.damage"])
	)
	var movement := AbilityEffectDefinition.new()
	_assert_equal(
		movement.configure_movement(
			"effect.synthetic.movement",
			PackedStringArray(["effect.movement"]),
			PackedStringArray(["effect.synthetic.status"]),
			"movement.dash",
			4.0,
			6
		),
		"",
		"Movement effect must configure."
	)
	var projectile := AbilityEffectDefinition.new()
	_assert_equal(
		projectile.configure_projectile(
			"effect.synthetic.projectile",
			PackedStringArray(["effect.projectile"]),
			PackedStringArray(["effect.synthetic.movement"]),
			"projectile.synthetic.storm_lance",
			18.0,
			120
		),
		"",
		"Projectile effect must configure."
	)
	var persistent := AbilityEffectDefinition.new()
	_assert_equal(
		persistent.configure_persistent_entity(
			"effect.synthetic.persistent",
			PackedStringArray(["effect.persistent"]),
			PackedStringArray(["effect.synthetic.projectile"]),
			"entity.synthetic.storm_echo",
			180
		),
		"",
		"Persistent effect must configure."
	)
	var event := AbilityEffectDefinition.new()
	_assert_equal(
		event.configure_event(
			"effect.synthetic.event",
			PackedStringArray(["effect.event"]),
			PackedStringArray(["effect.synthetic.persistent"]),
			"event.kill",
			{"reason": "synthetic"}
		),
		"",
		"Event effect must configure."
	)
	var error: String = ability.configure_ability(
		"ability.synthetic.storm_lance",
		["ability.damage", "delivery.projectile"],
		[],
		"resource.mana",
		18.0,
		90,
		12,
		8,
		AbilityDefinition.Targeting.ENTITY,
		AbilityDefinition.Delivery.PROJECTILE,
		[damage, status, movement, projectile, persistent, event],
		[]
	)
	assert(error.is_empty(), error)
	return ability


func _damage_effect(
	effect_id: String,
	base_amount: float,
	scaling_stat_id: String = ""
) -> RefCounted:
	var component := AbilityDamageComponent.new()
	var coefficient := 1.0 if not scaling_stat_id.is_empty() else 0.0
	var error: String = component.configure(
		"damage.lightning",
		base_amount,
		scaling_stat_id,
		coefficient,
		effect_id
	)
	assert(error.is_empty(), error)
	var more := _authored_damage_modifier(
		"damage.lightning",
		DamageModifier.Operation.MORE,
		0.5 if effect_id == "effect.synthetic.damage" else 0.0,
		"source.ability_more"
	)
	var effect := AbilityEffectDefinition.new()
	error = effect.configure_damage(
		effect_id,
		PackedStringArray(["damage.lightning"]),
		PackedStringArray(),
		[component],
		[more] if effect_id == "effect.synthetic.damage" else [],
		"stat.critical_chance" if effect_id == "effect.synthetic.damage" else "",
		"stat.critical_multiplier" if effect_id == "effect.synthetic.damage" else ""
	)
	assert(error.is_empty(), error)
	return effect


func _status_effect(
	effect_id: String,
	dependencies: PackedStringArray = PackedStringArray()
) -> RefCounted:
	var effect := AbilityEffectDefinition.new()
	var error: String = effect.configure_status(
		effect_id,
		PackedStringArray(["effect.status"]),
		dependencies,
		"status.synthetic.shocked",
		180,
		1
	)
	assert(error.is_empty(), error)
	return effect


func _transform(source_id: String, target_effect_id: String, replacement: RefCounted) -> RefCounted:
	var transform := AbilityEffectTransform.new()
	var error: String = transform.configure(source_id, target_effect_id, replacement)
	assert(error.is_empty(), error)
	return transform


func _milestone(minimum_rank: int, transforms: Array) -> RefCounted:
	var milestone := AbilityRankMilestone.new()
	var error: String = milestone.configure(minimum_rank, transforms)
	assert(error.is_empty(), error)
	return milestone


func _configure_ability(
	ability: RefCounted,
	effects: Array,
	milestones: Array = []
) -> String:
	return ability.configure_ability(
		"ability.synthetic.validation",
		["ability.validation"],
		[],
		"",
		0.0,
		0,
		0,
		0,
		AbilityDefinition.Targeting.ENTITY,
		AbilityDefinition.Delivery.INSTANT,
		effects,
		milestones
	)


func _execution_context(
	snapshot: RefCounted,
	rank: int,
	damage_modifiers: Array = [],
	critical_roll: float = 0.5
) -> RefCounted:
	var context := AbilityExecutionContext.new()
	var error: String = context.configure(
		rank,
		17,
		1,
		2,
		3,
		snapshot,
		critical_roll,
		PackedStringArray(),
		damage_modifiers,
		Vector2(4.0, 5.0),
		Vector2.RIGHT
	)
	assert(error.is_empty(), error)
	return context


func _snapshot(values: Dictionary) -> RefCounted:
	var definitions: Array = []
	for stat_id: String in values:
		var definition := StatDefinition.new()
		var error: String = definition.configure(stat_id, values[stat_id])
		assert(error.is_empty(), error)
		definitions.append(definition)
	var registry := StatRegistry.new()
	var errors: PackedStringArray = registry.load_definitions(definitions)
	assert(errors.is_empty(), str(errors))
	var result: RefCounted = StatResolver.resolve(
		registry,
		[],
		PackedStringArray(),
		17
	)
	assert(result.is_success(), str(result.errors()))
	return result.snapshot()


func _damage_modifier(
	damage_type_id: String,
	operation: int,
	value: float,
	source_id: String,
	target_damage_type_id: String = ""
) -> RefCounted:
	var modifier := DamageModifier.new()
	var error: String = modifier.configure(
		damage_type_id,
		operation,
		value,
		source_id,
		target_damage_type_id
	)
	assert(error.is_empty(), error)
	return modifier


func _authored_damage_modifier(
	damage_type_id: String,
	operation: int,
	value: float,
	source_id: String,
	target_damage_type_id: String = ""
) -> RefCounted:
	var modifier := AbilityDamageModifier.new()
	var error: String = modifier.configure(
		damage_type_id,
		operation,
		value,
		source_id,
		target_damage_type_id
	)
	assert(error.is_empty(), error)
	return modifier


func _effect_ids(effects: Array) -> Array[String]:
	var result: Array[String] = []
	for effect: RefCounted in effects:
		result.append(effect.effect_id())
	return result


func _output_kinds(outputs: Array) -> Array[int]:
	var result: Array[int] = []
	for output: RefCounted in outputs:
		result.append(output.kind())
	return result


func _breakdown_for(result: RefCounted, damage_type_id: String) -> Dictionary:
	for component: Dictionary in result.component_breakdown():
		if component["damage_type_id"] == damage_type_id:
			return component
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
