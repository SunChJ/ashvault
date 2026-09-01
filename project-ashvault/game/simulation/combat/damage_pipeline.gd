class_name DamagePipeline
extends RefCounted

const ContextContract = preload("res://game/simulation/combat/damage_context.gd")
const DamageModifierContract = preload("res://game/simulation/combat/damage_modifier.gd")
const DamageResultContract = preload("res://game/simulation/combat/damage_result.gd")
const ResolutionResult = preload("res://game/simulation/combat/damage_resolution_result.gd")

const MIN_RESISTANCE := -1.0
const MAX_RESISTANCE := 0.85
const DEFENSE_CONSTANT := 100.0

const STAGE_NAMES: Array[String] = [
	"BASE_FLAT",
	"INCREASED",
	"MORE",
	"CONVERSION",
	"CRITICAL",
	"DEFENSE",
	"RESISTANCE_PENETRATION",
	"CONDITIONAL",
	"FINAL_CLAMP",
]


static func resolve(context: Variant) -> RefCounted:
	if not context is ContextContract or not context.is_configured():
		return _resolution(
			null,
			PackedStringArray(["Damage resolution requires a configured DamageContext."])
		)

	var modifiers: Array = context.modifiers()
	var types := _collect_damage_types(context.base_components(), modifiers)
	var grouped := _group_modifiers(types, modifiers)
	var breakdown := _initial_breakdown(types)
	var source_breakdown: Array = []
	var contributing_sources: Dictionary = {}
	var active_conditions: Dictionary = {}
	for condition_id in context.active_conditions():
		active_conditions[StringName(condition_id)] = true

	_apply_base_and_flat(
		context.base_components(), grouped, breakdown,
		source_breakdown, contributing_sources
	)
	_apply_increased(grouped, breakdown, source_breakdown, contributing_sources)
	_apply_more(grouped, breakdown, source_breakdown, contributing_sources)
	_apply_conversions(grouped, breakdown, source_breakdown, contributing_sources)
	var is_critical: bool = context.critical_roll() < context.critical_chance()
	_apply_critical(breakdown, is_critical, context.critical_multiplier())
	var mitigation_breakdown := _apply_mitigation(
		grouped, breakdown, source_breakdown, contributing_sources
	)
	_apply_conditionals(
		grouped, breakdown, active_conditions,
		source_breakdown, contributing_sources
	)

	var total_damage := 0.0
	var critical_total := 0.0
	var mitigated_total := 0.0
	var component_breakdown: Array = []
	for damage_type_id in types:
		var entry: Dictionary = breakdown[StringName(damage_type_id)]
		entry["final"] = maxf(0.0, entry["conditional"])
		if not _breakdown_is_finite(entry):
			return _resolution(
				null,
				PackedStringArray([
					"Damage resolution produced a non-finite value for '%s'." % damage_type_id
				])
			)
		total_damage += entry["final"]
		critical_total += entry["critical"]
		mitigated_total += entry["resistance_penetration"]
		component_breakdown.append(entry)
	if not is_finite(total_damage):
		return _resolution(
			null,
			PackedStringArray(["Damage resolution produced a non-finite total."])
		)

	var source_ids := PackedStringArray()
	for source_id: StringName in contributing_sources:
		source_ids.append(String(source_id))
	source_ids.sort()
	var result := DamageResultContract.new()
	var configure_error: String = result._configure(
		context,
		is_critical,
		total_damage,
		maxf(0.0, critical_total - mitigated_total),
		component_breakdown,
		mitigation_breakdown,
		source_breakdown,
		source_ids
	)
	assert(configure_error.is_empty())
	return _resolution(result, PackedStringArray())


static func _collect_damage_types(components: Array, modifiers: Array) -> PackedStringArray:
	var observed: Dictionary = {}
	for component: RefCounted in components:
		observed[StringName(component.damage_type_id())] = true
	for modifier: RefCounted in modifiers:
		observed[StringName(modifier.damage_type_id())] = true
		if not modifier.target_damage_type_id().is_empty():
			observed[StringName(modifier.target_damage_type_id())] = true
	var result := PackedStringArray()
	for damage_type_id: StringName in observed:
		result.append(String(damage_type_id))
	result.sort()
	return result


static func _group_modifiers(types: PackedStringArray, modifiers: Array) -> Dictionary:
	var grouped: Dictionary = {}
	for damage_type_id in types:
		grouped[StringName(damage_type_id)] = {}
	for modifier: RefCounted in modifiers:
		var type_key := StringName(modifier.damage_type_id())
		var operation: int = modifier.operation()
		if not grouped[type_key].has(operation):
			grouped[type_key][operation] = []
		grouped[type_key][operation].append(modifier)
	return grouped


static func _initial_breakdown(types: PackedStringArray) -> Dictionary:
	var breakdown: Dictionary = {}
	for damage_type_id in types:
		breakdown[StringName(damage_type_id)] = {
			"damage_type_id": damage_type_id,
			"base_flat": 0.0,
			"increased": 0.0,
			"more": 0.0,
			"conversion": 0.0,
			"critical": 0.0,
			"defense": 0.0,
			"resistance_penetration": 0.0,
			"conditional": 0.0,
			"final": 0.0,
		}
	return breakdown


static func _apply_base_and_flat(
	components: Array,
	grouped: Dictionary,
	breakdown: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	for component: RefCounted in components:
		var type_key := StringName(component.damage_type_id())
		breakdown[type_key]["base_flat"] += component.amount()
		source_breakdown.append({
			"source_id": component.source_id(),
			"damage_type_id": component.damage_type_id(),
			"operation": "BASE",
			"value": component.amount(),
			"applied": true,
		})
		contributing_sources[StringName(component.source_id())] = true
	for type_key: StringName in breakdown:
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.FLAT, []):
			breakdown[type_key]["base_flat"] += modifier.amount()
			_record_modifier(modifier, source_breakdown, contributing_sources)


static func _apply_increased(
	grouped: Dictionary,
	breakdown: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	for type_key: StringName in breakdown:
		var bucket := 0.0
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.INCREASED, []):
			bucket += modifier.amount()
			_record_modifier(modifier, source_breakdown, contributing_sources)
		breakdown[type_key]["increased"] = (
			breakdown[type_key]["base_flat"] * maxf(0.0, 1.0 + bucket)
		)


static func _apply_more(
	grouped: Dictionary,
	breakdown: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	for type_key: StringName in breakdown:
		var current: float = breakdown[type_key]["increased"]
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.MORE, []):
			current *= maxf(0.0, 1.0 + modifier.amount())
			_record_modifier(modifier, source_breakdown, contributing_sources)
		breakdown[type_key]["more"] = current


static func _apply_conversions(
	grouped: Dictionary,
	breakdown: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	var deltas: Dictionary = {}
	for type_key: StringName in breakdown:
		deltas[type_key] = 0.0
	for type_key: StringName in breakdown:
		var remaining := 1.0
		var source_amount: float = breakdown[type_key]["more"]
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.CONVERSION, []):
			var applied_fraction := minf(modifier.amount(), remaining)
			var converted_amount := source_amount * applied_fraction
			deltas[type_key] -= converted_amount
			deltas[StringName(modifier.target_damage_type_id())] += converted_amount
			remaining -= applied_fraction
			var details: Dictionary = modifier.explanation_fields()
			details["applied"] = true
			details["applied_fraction"] = applied_fraction
			details["converted_amount"] = converted_amount
			source_breakdown.append(details)
			contributing_sources[StringName(modifier.source_id())] = true
	for type_key: StringName in breakdown:
		breakdown[type_key]["conversion"] = breakdown[type_key]["more"] + deltas[type_key]


static func _apply_critical(
	breakdown: Dictionary,
	is_critical: bool,
	critical_multiplier: float
) -> void:
	var multiplier := critical_multiplier if is_critical else 1.0
	for type_key: StringName in breakdown:
		breakdown[type_key]["critical"] = breakdown[type_key]["conversion"] * multiplier


static func _apply_mitigation(
	grouped: Dictionary,
	breakdown: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> Array:
	var result: Array = []
	for type_key: StringName in breakdown:
		var defense := 0.0
		var resistance := 0.0
		var penetration := 0.0
		var defense_sources := PackedStringArray()
		var resistance_sources := PackedStringArray()
		var penetration_sources := PackedStringArray()
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.DEFENSE, []):
			defense += modifier.amount()
			defense_sources.append(modifier.source_id())
			_record_modifier(modifier, source_breakdown, contributing_sources)
		var defense_input: float = breakdown[type_key]["critical"]
		var defense_output: float = defense_input * DEFENSE_CONSTANT / (DEFENSE_CONSTANT + defense)
		breakdown[type_key]["defense"] = defense_output
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.RESISTANCE, []):
			resistance += modifier.amount()
			resistance_sources.append(modifier.source_id())
			_record_modifier(modifier, source_breakdown, contributing_sources)
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.PENETRATION, []):
			penetration += modifier.amount()
			penetration_sources.append(modifier.source_id())
			_record_modifier(modifier, source_breakdown, contributing_sources)
		var effective_resistance := clampf(
			resistance - penetration,
			MIN_RESISTANCE,
			MAX_RESISTANCE
		)
		var resistance_output := defense_output * (1.0 - effective_resistance)
		breakdown[type_key]["resistance_penetration"] = resistance_output
		result.append({
			"damage_type_id": String(type_key),
			"input_damage": defense_input,
			"defense": defense,
			"defense_sources": defense_sources,
			"after_defense": defense_output,
			"resistance": resistance,
			"resistance_sources": resistance_sources,
			"penetration": penetration,
			"penetration_sources": penetration_sources,
			"effective_resistance": effective_resistance,
			"output_damage": resistance_output,
			"mitigated_amount": defense_input - resistance_output,
		})
	return result


static func _apply_conditionals(
	grouped: Dictionary,
	breakdown: Dictionary,
	active_conditions: Dictionary,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	for type_key: StringName in breakdown:
		var current: float = breakdown[type_key]["resistance_penetration"]
		for modifier: RefCounted in grouped[type_key].get(DamageModifierContract.Operation.CONDITIONAL, []):
			if not active_conditions.has(StringName(modifier.condition_id())):
				var skipped: Dictionary = modifier.explanation_fields()
				skipped["applied"] = false
				skipped["reason"] = "inactive_condition"
				source_breakdown.append(skipped)
				continue
			current *= maxf(0.0, 1.0 + modifier.amount())
			_record_modifier(modifier, source_breakdown, contributing_sources)
		breakdown[type_key]["conditional"] = current


static func _record_modifier(
	modifier: RefCounted,
	source_breakdown: Array,
	contributing_sources: Dictionary
) -> void:
	var details: Dictionary = modifier.explanation_fields()
	details["applied"] = true
	source_breakdown.append(details)
	contributing_sources[StringName(modifier.source_id())] = true


static func _breakdown_is_finite(entry: Dictionary) -> bool:
	for field in [
		"base_flat", "increased", "more", "conversion", "critical",
		"defense", "resistance_penetration", "conditional", "final",
	]:
		if not is_finite(entry[field]):
			return false
	return true


static func _resolution(result: RefCounted, errors: PackedStringArray) -> RefCounted:
	var resolution := ResolutionResult.new()
	resolution._configure(result, errors)
	return resolution
