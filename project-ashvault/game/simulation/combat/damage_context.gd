class_name DamageContext
extends RefCounted

const ComponentContract = preload("res://game/simulation/combat/damage_component.gd")
const ModifierContract = preload("res://game/simulation/combat/damage_modifier.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")

const MAX_CRITICAL_CHANCE := 0.95

var _source_entity_id := 0
var _target_entity_id := 0
var _ability_id := ""
var _origin_event_id := 0
var _tags := PackedStringArray()
var _base_components: Array = []
var _modifiers: Array = []
var _active_conditions := PackedStringArray()
var _critical_chance := 0.0
var _critical_multiplier := 1.0
var _critical_roll := 0.0
var _is_configured := false


func configure(
	source_entity_id: int,
	target_entity_id: int,
	ability_id: String,
	origin_event_id: int,
	tags: PackedStringArray,
	base_components: Array,
	modifiers: Array,
	active_conditions: PackedStringArray,
	critical_chance: float,
	critical_multiplier: float,
	critical_roll: float
) -> String:
	if _is_configured:
		return "Damage context for '%s' is already configured and immutable." % _ability_id
	if source_entity_id <= 0 or target_entity_id <= 0:
		return "Damage context runtime entity IDs must be positive."
	if origin_event_id <= 0:
		return "Damage context origin event ID must be positive."
	var ability_error := StableIdContract.validation_error(ability_id)
	if not ability_error.is_empty():
		return ability_error
	var tag_error := _validate_stable_ids(tags, "tag")
	if not tag_error.is_empty():
		return tag_error
	var condition_error := _validate_stable_ids(active_conditions, "active condition")
	if not condition_error.is_empty():
		return condition_error
	if base_components.is_empty():
		return "Damage context requires at least one base component."
	for index in base_components.size():
		var component: Variant = base_components[index]
		if not component is ComponentContract or not component.is_configured():
			return "Base damage component at index %d is not configured." % index
	var identities: Dictionary = {}
	for index in modifiers.size():
		var modifier: Variant = modifiers[index]
		if not modifier is ModifierContract or not modifier.is_configured():
			return "Damage modifier at index %d is not configured." % index
		var identity: String = modifier.identity_key()
		if identities.has(identity):
			return "Duplicate damage modifier '%s'." % identity
		identities[identity] = true
	if not is_finite(critical_chance) or critical_chance < 0.0 or critical_chance > MAX_CRITICAL_CHANCE:
		return "Critical chance must be finite and between 0 and %s." % MAX_CRITICAL_CHANCE
	if not is_finite(critical_multiplier) or critical_multiplier < 1.0:
		return "Critical multiplier must be finite and at least 1."
	if not is_finite(critical_roll) or critical_roll < 0.0 or critical_roll > 1.0:
		return "Critical roll must be finite and between 0 and 1."

	_source_entity_id = source_entity_id
	_target_entity_id = target_entity_id
	_ability_id = ability_id
	_origin_event_id = origin_event_id
	_tags = tags.duplicate()
	_tags.sort()
	_base_components = base_components.duplicate()
	_base_components.sort_custom(_component_precedes)
	_modifiers = modifiers.duplicate()
	_modifiers.sort_custom(_modifier_precedes)
	_active_conditions = active_conditions.duplicate()
	_active_conditions.sort()
	_critical_chance = critical_chance
	_critical_multiplier = critical_multiplier
	_critical_roll = critical_roll
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func ability_id() -> String:
	return _ability_id


func origin_event_id() -> int:
	return _origin_event_id


func tags() -> PackedStringArray:
	return _tags.duplicate()


func base_components() -> Array:
	return _base_components.duplicate()


func modifiers() -> Array:
	return _modifiers.duplicate()


func active_conditions() -> PackedStringArray:
	return _active_conditions.duplicate()


func critical_chance() -> float:
	return _critical_chance


func critical_multiplier() -> float:
	return _critical_multiplier


func critical_roll() -> float:
	return _critical_roll


static func _validate_stable_ids(values: PackedStringArray, label: String) -> String:
	var observed: Dictionary = {}
	for value in values:
		var id_error := StableIdContract.validation_error(value)
		if not id_error.is_empty():
			return "Invalid %s: %s" % [label, id_error]
		if observed.has(value):
			return "Duplicate %s '%s'." % [label, value]
		observed[value] = true
	return ""


static func _component_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.damage_type_id() != right.damage_type_id():
		return left.damage_type_id() < right.damage_type_id()
	if left.source_id() != right.source_id():
		return left.source_id() < right.source_id()
	return left.amount() < right.amount()


static func _modifier_precedes(left: RefCounted, right: RefCounted) -> bool:
	if left.priority() != right.priority():
		return left.priority() > right.priority()
	if left.source_id() != right.source_id():
		return left.source_id() < right.source_id()
	if left.operation() != right.operation():
		return left.operation() < right.operation()
	if left.damage_type_id() != right.damage_type_id():
		return left.damage_type_id() < right.damage_type_id()
	if left.target_damage_type_id() != right.target_damage_type_id():
		return left.target_damage_type_id() < right.target_damage_type_id()
	if left.condition_id() != right.condition_id():
		return left.condition_id() < right.condition_id()
	return left.amount() < right.amount()
