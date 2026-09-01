class_name AbilityExecutor
extends RefCounted

const AbilityContract = preload(
	"res://game/simulation/abilities/ability_definition.gd"
)
const Command = preload(
	"res://game/simulation/abilities/ability_effect_command.gd"
)
const ContextContract = preload(
	"res://game/simulation/abilities/ability_execution_context.gd"
)
const EffectContract = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const ExecutionResult = preload(
	"res://game/simulation/abilities/ability_execution_result.gd"
)
const Output = preload(
	"res://game/simulation/abilities/ability_effect_output.gd"
)
const DamageComponent = preload(
	"res://game/simulation/combat/damage_component.gd"
)
const DamageContext = preload("res://game/simulation/combat/damage_context.gd")
const DamagePipeline = preload("res://game/simulation/combat/damage_pipeline.gd")
const EventRequest = preload("res://game/simulation/events/combat_event_request.gd")


static func execute(definition: Variant, context: Variant) -> RefCounted:
	if not definition is AbilityContract or not definition.is_configured():
		return _result([], "Ability execution requires a configured AbilityDefinition.")
	if not context is ContextContract or not context.is_configured():
		return _result([], "Ability execution requires a configured execution context.")
	var target_error := _validate_target(definition, context)
	if not target_error.is_empty():
		return _result([], target_error)

	var staged_outputs: Array = []
	for effect: Resource in definition.effects_for_rank(context.rank()):
		var resolved := _execute_effect(definition, effect, context)
		var error: String = resolved["error"]
		if not error.is_empty():
			return _result([], "Effect '%s': %s" % [effect.effect_id(), error])
		staged_outputs.append(resolved["output"])
	return _result(staged_outputs, "")


static func _validate_target(definition: Resource, context: RefCounted) -> String:
	match definition.targeting():
		AbilityContract.Targeting.ENTITY:
			if context.target_entity_id() <= 0:
				return "Entity-targeted ability requires a positive target entity ID."
		AbilityContract.Targeting.DIRECTION:
			if context.direction().is_zero_approx():
				return "Direction-targeted ability requires a non-zero direction."
	return ""


static func _execute_effect(
	definition: Resource,
	effect: Resource,
	context: RefCounted
) -> Dictionary:
	match effect.kind():
		EffectContract.Kind.DAMAGE:
			return _execute_damage(definition, effect, context)
		EffectContract.Kind.EVENT:
			return _execute_event(definition, effect, context)
		EffectContract.Kind.STATUS, EffectContract.Kind.MOVEMENT, EffectContract.Kind.PROJECTILE, EffectContract.Kind.PERSISTENT_ENTITY:
			var command := Command.new()
			command._configure(
				effect,
				context.source_entity_id(),
				_effective_target(definition, context),
				context.target_position(),
				context.direction()
			)
			return {
				"output": _output(effect, null, command, null),
				"error": "",
			}
	return {"output": null, "error": "Unknown effect kind '%s'." % effect.kind()}


static func _execute_damage(
	definition: Resource,
	effect: Resource,
	context: RefCounted
) -> Dictionary:
	var target_entity_id := _effective_target(definition, context)
	if target_entity_id <= 0:
		return {"output": null, "error": "Damage effect requires a target entity."}
	var snapshot: RefCounted = context.stat_snapshot()
	var runtime_components: Array = []
	for component: Resource in effect.damage_components():
		var amount: float = component.base_amount()
		if not component.scaling_stat_id().is_empty():
			if not snapshot.has_stat(component.scaling_stat_id()):
				return {
					"output": null,
					"error": "Missing scaling stat '%s'." % component.scaling_stat_id(),
				}
			amount += (
				snapshot.value(component.scaling_stat_id())
				* component.scaling_coefficient()
			)
		var runtime_component := DamageComponent.new()
		var component_error: String = runtime_component.configure(
			component.damage_type_id(),
			maxf(0.0, amount),
			component.source_id()
		)
		if not component_error.is_empty():
			return {"output": null, "error": component_error}
		runtime_components.append(runtime_component)

	var runtime_modifiers: Array = []
	for authored_modifier: Resource in effect.damage_modifiers():
		runtime_modifiers.append(authored_modifier.to_runtime())
	runtime_modifiers.append_array(context.damage_modifiers())
	var critical_chance_result := _stat_value(
		snapshot,
		effect.critical_chance_stat_id(),
		0.0
	)
	if not critical_chance_result["error"].is_empty():
		return {"output": null, "error": critical_chance_result["error"]}
	var critical_multiplier_result := _stat_value(
		snapshot,
		effect.critical_multiplier_stat_id(),
		1.0
	)
	if not critical_multiplier_result["error"].is_empty():
		return {"output": null, "error": critical_multiplier_result["error"]}

	var damage_context := DamageContext.new()
	var context_error: String = damage_context.configure(
		context.source_entity_id(),
		target_entity_id,
		definition.content_id,
		context.origin_event_id(),
		_merge_tags(definition.tags, effect.tags()),
		runtime_components,
		runtime_modifiers,
		context.active_conditions(),
		critical_chance_result["value"],
		critical_multiplier_result["value"],
		context.critical_roll()
	)
	if not context_error.is_empty():
		return {"output": null, "error": context_error}
	var resolution: RefCounted = DamagePipeline.resolve(damage_context)
	if not resolution.is_success():
		return {"output": null, "error": "; ".join(resolution.errors())}
	return {
		"output": _output(effect, resolution.result(), null, null),
		"error": "",
	}


static func _execute_event(
	definition: Resource,
	effect: Resource,
	context: RefCounted
) -> Dictionary:
	var request := EventRequest.new()
	var error: String = request.configure(
		effect.event_type(),
		context.source_entity_id(),
		_effective_target(definition, context),
		definition.content_id,
		_merge_tags(definition.tags, effect.tags()),
		effect.event_payload()
	)
	if not error.is_empty():
		return {"output": null, "error": error}
	return {
		"output": _output(effect, null, null, request),
		"error": "",
	}


static func _stat_value(
	snapshot: RefCounted,
	stat_id: String,
	default_value: float
) -> Dictionary:
	if stat_id.is_empty():
		return {"value": default_value, "error": ""}
	if not snapshot.has_stat(stat_id):
		return {"value": NAN, "error": "Missing stat '%s'." % stat_id}
	return {"value": snapshot.value(stat_id), "error": ""}


static func _effective_target(definition: Resource, context: RefCounted) -> int:
	if definition.targeting() == AbilityContract.Targeting.SELF:
		return context.source_entity_id()
	return context.target_entity_id()


static func _merge_tags(
	ability_tags: Array[String],
	effect_tags: PackedStringArray
) -> PackedStringArray:
	var observed: Dictionary = {}
	for tag in ability_tags:
		observed[tag] = true
	for tag in effect_tags:
		observed[tag] = true
	var result := PackedStringArray()
	for tag: String in observed:
		result.append(tag)
	result.sort()
	return result


static func _output(
	effect: Resource,
	damage_result: RefCounted,
	command: RefCounted,
	event_request: RefCounted
) -> RefCounted:
	var output := Output.new()
	output._configure(
		effect.effect_id(),
		effect.kind(),
		damage_result,
		command,
		event_request
	)
	return output


static func _result(outputs: Array, error: String) -> RefCounted:
	var errors := PackedStringArray()
	if not error.is_empty():
		errors.append(error)
	var result := ExecutionResult.new()
	result._configure(outputs, errors)
	return result
