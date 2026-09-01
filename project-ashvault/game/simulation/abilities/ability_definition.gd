class_name AbilityDefinition
extends "res://game/content/content_definition.gd"

const EffectContract = preload(
	"res://game/simulation/abilities/ability_effect_definition.gd"
)
const MilestoneContract = preload(
	"res://game/simulation/abilities/ability_rank_milestone.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

enum Targeting {
	SELF,
	ENTITY,
	POINT,
	DIRECTION,
}

enum Delivery {
	INSTANT,
	PROJECTILE,
	AREA,
	CHAIN,
	PERSISTENT,
	MOVEMENT,
}

const TARGETING_NAMES: Array[String] = ["SELF", "ENTITY", "POINT", "DIRECTION"]
const DELIVERY_NAMES: Array[String] = [
	"INSTANT",
	"PROJECTILE",
	"AREA",
	"CHAIN",
	"PERSISTENT",
	"MOVEMENT",
]

var _cost_resource_id := ""
var _cost_amount := 0.0
var _cooldown_ticks := 0
var _cast_time_ticks := 0
var _recovery_ticks := 0
var _targeting := -1
var _delivery := -1
var _effects: Array = []
var _milestones: Array = []
var _is_configured := false


func configure_ability(
	ability_id: String,
	ability_tags: Array,
	content_dependencies: Array,
	cost_resource_id: String,
	cost_amount: float,
	cooldown_ticks: int,
	cast_time_ticks: int,
	recovery_ticks: int,
	targeting: int,
	delivery: int,
	effects: Array,
	milestones: Array
) -> String:
	if _is_configured:
		return "Ability definition '%s' is already configured and immutable." % content_id
	var ability_error := StableIdContract.validation_error(ability_id)
	if not ability_error.is_empty():
		return ability_error
	var tags_error := _validate_stable_array(ability_tags, "ability tag")
	if not tags_error.is_empty():
		return tags_error
	var dependencies_error := _validate_stable_array(
		content_dependencies,
		"content dependency"
	)
	if not dependencies_error.is_empty():
		return dependencies_error
	if cost_resource_id.is_empty():
		if cost_amount != 0.0:
			return "Abilities without a resource ID must have zero cost."
	else:
		var resource_error := StableIdContract.validation_error(cost_resource_id)
		if not resource_error.is_empty():
			return resource_error
	if not is_finite(cost_amount) or cost_amount < 0.0:
		return "Ability resource cost must be finite and non-negative."
	if cooldown_ticks < 0 or cast_time_ticks < 0 or recovery_ticks < 0:
		return "Ability cooldown and cast timing ticks must be non-negative."
	if targeting < Targeting.SELF or targeting > Targeting.DIRECTION:
		return "Unknown ability targeting mode '%s'." % targeting
	if delivery < Delivery.INSTANT or delivery > Delivery.MOVEMENT:
		return "Unknown ability delivery mode '%s'." % delivery
	if effects.is_empty():
		return "Ability '%s' requires at least one effect." % ability_id

	var graph_error := _validate_effect_graph(effects)
	if not graph_error.is_empty():
		return graph_error
	var delivery_error := _validate_delivery(delivery, effects)
	if not delivery_error.is_empty():
		return delivery_error
	var milestones_error := _validate_milestones(effects, milestones, delivery)
	if not milestones_error.is_empty():
		return milestones_error

	var typed_tags: Array[String] = []
	for tag: String in ability_tags:
		typed_tags.append(tag)
	var typed_dependencies: Array[String] = []
	for dependency: String in content_dependencies:
		typed_dependencies.append(dependency)
	var base_error: String = super.configure(
		ability_id,
		typed_tags,
		typed_dependencies
	)
	if not base_error.is_empty():
		return base_error
	_cost_resource_id = cost_resource_id
	_cost_amount = cost_amount
	_cooldown_ticks = cooldown_ticks
	_cast_time_ticks = cast_time_ticks
	_recovery_ticks = recovery_ticks
	_targeting = targeting
	_delivery = delivery
	_effects = effects.duplicate()
	_milestones = milestones.duplicate()
	_milestones.sort_custom(_milestone_precedes)
	_is_configured = true
	return ""


func configure(
	new_content_id: String,
	new_tags: Array[String],
	new_dependencies: Array[String]
) -> String:
	if _is_configured:
		return "Ability definition '%s' is immutable." % content_id
	return super.configure(new_content_id, new_tags, new_dependencies)


func is_configured() -> bool:
	return _is_configured


func cost_resource_id() -> String:
	return _cost_resource_id


func cost_amount() -> float:
	return _cost_amount


func cooldown_ticks() -> int:
	return _cooldown_ticks


func cast_time_ticks() -> int:
	return _cast_time_ticks


func recovery_ticks() -> int:
	return _recovery_ticks


func targeting() -> int:
	return _targeting


func delivery() -> int:
	return _delivery


func milestones() -> Array:
	return _milestones.duplicate()


func effects_for_rank(rank: int) -> Array:
	if not _is_configured or rank < 1:
		return []
	var resolved: Array = _effects.duplicate()
	for milestone: Resource in _milestones:
		if milestone.minimum_rank() > rank:
			break
		_apply_transforms(resolved, milestone.transforms())
	return _ordered_effects(resolved)


static func _validate_stable_array(values: Array, label: String) -> String:
	var observed: Dictionary = {}
	for value: Variant in values:
		if not value is String:
			return "%s values must be strings." % label.capitalize()
		var id_error := StableIdContract.validation_error(value)
		if not id_error.is_empty():
			return "Invalid %s: %s" % [label, id_error]
		if observed.has(value):
			return "Duplicate %s '%s'." % [label, value]
		observed[value] = true
	return ""


static func _validate_effect_graph(effects: Array) -> String:
	var by_id: Dictionary = {}
	for index in effects.size():
		var effect: Variant = effects[index]
		if not effect is EffectContract or not effect.is_configured():
			return "Ability effect at index %d is not configured." % index
		if by_id.has(effect.effect_id()):
			return "Duplicate effect ID '%s'." % effect.effect_id()
		by_id[effect.effect_id()] = effect
	for effect: Resource in effects:
		for dependency_id in effect.dependency_ids():
			if not by_id.has(dependency_id):
				return "Effect '%s' has unknown dependency '%s'." % [
					effect.effect_id(),
					dependency_id,
				]
	if _ordered_effects(effects).size() != effects.size():
		return "Ability effect graph contains a dependency cycle."
	return ""


static func _validate_delivery(delivery: int, effects: Array) -> String:
	var required_kind := -1
	match delivery:
		Delivery.PROJECTILE:
			required_kind = EffectContract.Kind.PROJECTILE
		Delivery.PERSISTENT:
			required_kind = EffectContract.Kind.PERSISTENT_ENTITY
		Delivery.MOVEMENT:
			required_kind = EffectContract.Kind.MOVEMENT
	if required_kind < 0:
		return ""
	for effect: Resource in effects:
		if effect.kind() == required_kind:
			return ""
	return "Ability delivery '%s' requires a %s effect." % [
		DELIVERY_NAMES[delivery],
		EffectContract.kind_name(required_kind),
	]


static func _validate_milestones(
	base_effects: Array,
	milestones: Array,
	delivery: int
) -> String:
	var observed_ranks: Dictionary = {}
	var sorted: Array = milestones.duplicate()
	for index in sorted.size():
		var milestone: Variant = sorted[index]
		if not milestone is MilestoneContract or not milestone.is_configured():
			return "Ability rank milestone at index %d is not configured." % index
		if observed_ranks.has(milestone.minimum_rank()):
			return "Duplicate ability milestone rank %d." % milestone.minimum_rank()
		observed_ranks[milestone.minimum_rank()] = true
	sorted.sort_custom(_milestone_precedes)
	var staged: Array = base_effects.duplicate()
	for milestone: Resource in sorted:
		var transform_error := _apply_transforms(staged, milestone.transforms())
		if not transform_error.is_empty():
			return "Ability milestone rank %d: %s" % [
				milestone.minimum_rank(),
				transform_error,
			]
		var graph_error := _validate_effect_graph(staged)
		if not graph_error.is_empty():
			return "Ability milestone rank %d: %s" % [
				milestone.minimum_rank(),
				graph_error,
			]
		var delivery_error := _validate_delivery(delivery, staged)
		if not delivery_error.is_empty():
			return "Ability milestone rank %d: %s" % [
				milestone.minimum_rank(),
				delivery_error,
			]
	return ""


static func _apply_transforms(effects: Array, transforms: Array) -> String:
	for transform: Resource in transforms:
		var replacement_index := -1
		for index in effects.size():
			if effects[index].effect_id() == transform.target_effect_id():
				replacement_index = index
				break
		if replacement_index < 0:
			return "Transform '%s' has unknown target '%s'." % [
				transform.source_id(),
				transform.target_effect_id(),
			]
		effects[replacement_index] = transform.replacement()
	return ""


static func _ordered_effects(effects: Array) -> Array:
	var result: Array = []
	var emitted: Dictionary = {}
	while result.size() < effects.size():
		var progressed := false
		for effect: Resource in effects:
			if emitted.has(effect.effect_id()):
				continue
			var ready := true
			for dependency_id in effect.dependency_ids():
				if not emitted.has(dependency_id):
					ready = false
					break
			if not ready:
				continue
			result.append(effect)
			emitted[effect.effect_id()] = true
			progressed = true
		if not progressed:
			return []
	return result


static func _milestone_precedes(left: Resource, right: Resource) -> bool:
	return left.minimum_rank() < right.minimum_rank()
