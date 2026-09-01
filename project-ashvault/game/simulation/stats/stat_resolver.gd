class_name StatResolver
extends RefCounted

const ResolutionResult = preload(
	"res://game/simulation/stats/stat_resolution_result.gd"
)
const Snapshot = preload("res://game/simulation/stats/stat_snapshot.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
const StatModifierContract = preload("res://game/simulation/stats/stat_modifier.gd")
const StatRegistryContract = preload("res://game/simulation/stats/stat_registry.gd")


static func resolve(
	registry: Variant,
	modifiers: Array,
	active_conditions: PackedStringArray,
	tick: int
) -> RefCounted:
	var errors := _validate_inputs(registry, modifiers, active_conditions, tick)
	if not errors.is_empty():
		return _result(null, errors)

	var active_condition_set: Dictionary = {}
	for condition_id in active_conditions:
		active_condition_set[StringName(condition_id)] = true
	var grouped: Dictionary = {}
	var explanations: Dictionary = _initial_explanations(registry)
	var sorted_modifiers: Array = modifiers.duplicate()
	sorted_modifiers.sort_custom(_modifier_precedes)
	for modifier: RefCounted in sorted_modifiers:
		var stat_key := StringName(modifier.stat_id())
		if not modifier.condition_id().is_empty() and not active_condition_set.has(
			StringName(modifier.condition_id())
		):
			var skipped: Dictionary = modifier.explanation_fields()
			skipped["reason"] = "inactive_condition"
			explanations[stat_key]["skipped_sources"].append(skipped)
			continue
		if not grouped.has(stat_key):
			grouped[stat_key] = {}
		var operation: int = modifier.operation()
		if not grouped[stat_key].has(operation):
			grouped[stat_key][operation] = []
		grouped[stat_key][operation].append(modifier)

	var values: Dictionary = _resolve_pre_conversion(registry, grouped, explanations)
	_apply_conversions(registry, grouped, values, explanations)
	_apply_overrides_and_caps(registry, grouped, values, explanations)
	for stat_id in registry.ids():
		if not is_finite(values[StringName(stat_id)]):
			errors.append("Resolved stat '%s' is not finite." % stat_id)
		explanations[StringName(stat_id)]["final_value"] = values[StringName(stat_id)]
	if not errors.is_empty():
		return _result(null, errors)

	var snapshot := Snapshot.new()
	var snapshot_error: String = snapshot._configure(tick, values, explanations)
	assert(snapshot_error.is_empty())
	return _result(snapshot, errors)


static func _validate_inputs(
	registry: Variant,
	modifiers: Array,
	active_conditions: PackedStringArray,
	tick: int
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not registry is StatRegistryContract or not registry.is_loaded():
		errors.append("Stat resolution requires a loaded StatRegistry.")
		return errors
	if tick < 0:
		errors.append("Stat snapshot tick must be non-negative.")

	var observed_conditions: Dictionary = {}
	for condition_id in active_conditions:
		var condition_error: String = StableIdContract.validation_error(condition_id)
		if not condition_error.is_empty():
			errors.append("Invalid active condition '%s': %s" % [condition_id, condition_error])
		var condition_key := StringName(condition_id)
		if observed_conditions.has(condition_key):
			errors.append("Duplicate active condition '%s'." % condition_id)
		observed_conditions[condition_key] = true

	var observed_modifiers: Dictionary = {}
	for index in modifiers.size():
		var modifier: Variant = modifiers[index]
		if not modifier is StatModifierContract or not modifier.is_configured():
			errors.append("Modifier at index %d is not configured." % index)
			continue
		if not registry.contains(modifier.stat_id()):
			errors.append("Unknown stat ID '%s'." % modifier.stat_id())
		if (
			modifier.operation() == StatModifierContract.Operation.CONVERSION
			and not registry.contains(modifier.target_stat_id())
		):
			errors.append(
				"Unknown conversion target '%s'." % modifier.target_stat_id()
			)
		var identity: String = modifier.identity_key()
		if observed_modifiers.has(identity):
			errors.append("Duplicate modifier '%s'." % identity)
		observed_modifiers[identity] = true

	errors.sort()
	return errors


static func _initial_explanations(registry: RefCounted) -> Dictionary:
	var explanations: Dictionary = {}
	for stat_id in registry.ids():
		var definition: RefCounted = registry.get_definition(stat_id)
		explanations[StringName(stat_id)] = {
			"stat_id": stat_id,
			"default_value": definition.default_value(),
			"final_value": definition.default_value(),
			"applied_sources": [],
			"skipped_sources": [],
			"incoming_conversions": [],
		}
	return explanations


static func _resolve_pre_conversion(
	registry: RefCounted,
	grouped: Dictionary,
	explanations: Dictionary
) -> Dictionary:
	var values: Dictionary = {}
	for stat_id in registry.ids():
		var stat_key := StringName(stat_id)
		var current: float = registry.get_definition(stat_id).default_value()
		var operations: Dictionary = grouped.get(stat_key, {})
		for operation in [
			StatModifierContract.Operation.BASE,
			StatModifierContract.Operation.FLAT,
		]:
			for modifier: RefCounted in operations.get(operation, []):
				var input: float = current
				current += modifier.amount()
				_append_applied(explanations[stat_key], modifier, input, current)

		var increased: Array = operations.get(
			StatModifierContract.Operation.INCREASED,
			[]
		)
		if not increased.is_empty():
			var input: float = current
			var bucket := 0.0
			for modifier: RefCounted in increased:
				bucket += modifier.amount()
			current *= 1.0 + bucket
			for modifier: RefCounted in increased:
				var entry: Dictionary = modifier.explanation_fields()
				entry["input_value"] = input
				entry["output_value"] = current
				entry["bucket_total"] = bucket
				explanations[stat_key]["applied_sources"].append(entry)

		for modifier: RefCounted in operations.get(
			StatModifierContract.Operation.MORE,
			[]
		):
			var input: float = current
			current *= 1.0 + modifier.amount()
			_append_applied(explanations[stat_key], modifier, input, current)
		values[stat_key] = current
	return values


static func _apply_conversions(
	registry: RefCounted,
	grouped: Dictionary,
	values: Dictionary,
	explanations: Dictionary
) -> void:
	var deltas: Dictionary = {}
	for stat_id in registry.ids():
		deltas[StringName(stat_id)] = 0.0

	for stat_id in registry.ids():
		var source_key := StringName(stat_id)
		var operations: Dictionary = grouped.get(source_key, {})
		var conversions: Array = operations.get(
			StatModifierContract.Operation.CONVERSION,
			[]
		)
		var remaining := 1.0
		var source_value: float = values[source_key]
		for modifier: RefCounted in conversions:
			var applied_fraction: float = minf(modifier.amount(), remaining)
			var converted_value: float = source_value * applied_fraction
			var target_key := StringName(modifier.target_stat_id())
			deltas[source_key] -= converted_value
			deltas[target_key] += converted_value
			remaining -= applied_fraction
			var entry: Dictionary = modifier.explanation_fields()
			entry["requested_fraction"] = modifier.amount()
			entry["applied_fraction"] = applied_fraction
			entry["converted_value"] = converted_value
			explanations[source_key]["applied_sources"].append(entry)
			explanations[target_key]["incoming_conversions"].append({
				"source_stat_id": stat_id,
				"source_id": modifier.source_id(),
				"applied_fraction": applied_fraction,
				"converted_value": converted_value,
			})

	for stat_id in registry.ids():
		var stat_key := StringName(stat_id)
		values[stat_key] += deltas[stat_key]


static func _apply_overrides_and_caps(
	registry: RefCounted,
	grouped: Dictionary,
	values: Dictionary,
	explanations: Dictionary
) -> void:
	for stat_id in registry.ids():
		var stat_key := StringName(stat_id)
		var operations: Dictionary = grouped.get(stat_key, {})
		var overrides: Array = operations.get(
			StatModifierContract.Operation.OVERRIDE,
			[]
		)
		if not overrides.is_empty():
			var winner: RefCounted = overrides[0]
			var input: float = values[stat_key]
			values[stat_key] = winner.amount()
			_append_applied(explanations[stat_key], winner, input, values[stat_key])
			for index in range(1, overrides.size()):
				var skipped: Dictionary = overrides[index].explanation_fields()
				skipped["reason"] = "lower_precedence_override"
				explanations[stat_key]["skipped_sources"].append(skipped)

		for modifier: RefCounted in operations.get(
			StatModifierContract.Operation.CAP,
			[]
		):
			var input: float = values[stat_key]
			values[stat_key] = minf(input, modifier.amount())
			_append_applied(
				explanations[stat_key],
				modifier,
				input,
				values[stat_key]
			)


static func _append_applied(
	explanation: Dictionary,
	modifier: RefCounted,
	input: float,
	output: float
) -> void:
	var entry: Dictionary = modifier.explanation_fields()
	entry["input_value"] = input
	entry["output_value"] = output
	explanation["applied_sources"].append(entry)


static func _modifier_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.priority() != right.priority():
		return left.priority() > right.priority()
	if left.source_id() != right.source_id():
		return left.source_id() < right.source_id()
	if left.operation() != right.operation():
		return left.operation() < right.operation()
	if left.stat_id() != right.stat_id():
		return left.stat_id() < right.stat_id()
	if left.condition_id() != right.condition_id():
		return left.condition_id() < right.condition_id()
	if left.target_stat_id() != right.target_stat_id():
		return left.target_stat_id() < right.target_stat_id()
	return left.amount() < right.amount()


static func _result(snapshot: RefCounted, errors: PackedStringArray) -> RefCounted:
	var result := ResolutionResult.new()
	result._configure(snapshot, errors)
	return result
