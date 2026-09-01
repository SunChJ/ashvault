class_name AbilityEffectDefinition
extends Resource

const AuthoredDamageModifier = preload(
	"res://game/simulation/abilities/ability_damage_modifier.gd"
)
const DamageComponentContract = preload(
	"res://game/simulation/abilities/ability_damage_component.gd"
)
const EventRequest = preload("res://game/simulation/events/combat_event_request.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")

enum Kind {
	DAMAGE,
	STATUS,
	MOVEMENT,
	PROJECTILE,
	PERSISTENT_ENTITY,
	EVENT,
}

const KIND_NAMES: Array[String] = [
	"DAMAGE",
	"STATUS",
	"MOVEMENT",
	"PROJECTILE",
	"PERSISTENT_ENTITY",
	"EVENT",
]

var _effect_id := ""
var _kind := -1
var _tags := PackedStringArray()
var _dependency_ids := PackedStringArray()
var _damage_components: Array = []
var _damage_modifiers: Array = []
var _critical_chance_stat_id := ""
var _critical_multiplier_stat_id := ""
var _status_definition_id := ""
var _duration_ticks := 0
var _stacks := 0
var _movement_mode_id := ""
var _distance := 0.0
var _projectile_definition_id := ""
var _speed := 0.0
var _lifetime_ticks := 0
var _entity_definition_id := ""
var _event_type := ""
var _event_payload: Dictionary = {}
var _is_configured := false


func configure_damage(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	components: Array,
	modifiers: Array,
	critical_chance_stat_id: String = "",
	critical_multiplier_stat_id: String = ""
) -> String:
	var common_error := _validate_common(effect_id, Kind.DAMAGE, tags, dependency_ids)
	if not common_error.is_empty():
		return common_error
	if components.is_empty():
		return "Damage effect '%s' requires at least one component." % effect_id
	var component_identities: Dictionary = {}
	for index in components.size():
		var component: Variant = components[index]
		if not component is DamageComponentContract or not component.is_configured():
			return "Ability damage component at index %d is not configured." % index
		if component_identities.has(component.identity_key()):
			return "Damage effect '%s' repeats component '%s'." % [
				effect_id,
				component.identity_key(),
			]
		component_identities[component.identity_key()] = true
	var modifier_identities: Dictionary = {}
	for index in modifiers.size():
		var modifier: Variant = modifiers[index]
		if not modifier is AuthoredDamageModifier or not modifier.is_configured():
			return "Authored damage modifier at index %d is not configured." % index
		if modifier_identities.has(modifier.identity_key()):
			return "Damage effect '%s' repeats modifier '%s'." % [
				effect_id,
				modifier.identity_key(),
			]
		modifier_identities[modifier.identity_key()] = true
	for stat_id in [critical_chance_stat_id, critical_multiplier_stat_id]:
		if not stat_id.is_empty():
			var stat_error := StableIdContract.validation_error(stat_id)
			if not stat_error.is_empty():
				return stat_error

	_publish_common(effect_id, Kind.DAMAGE, tags, dependency_ids)
	_damage_components = components.duplicate()
	_damage_modifiers = modifiers.duplicate()
	_critical_chance_stat_id = critical_chance_stat_id
	_critical_multiplier_stat_id = critical_multiplier_stat_id
	return ""


func configure_status(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	status_definition_id: String,
	duration_ticks: int,
	stacks: int
) -> String:
	var common_error := _validate_common(effect_id, Kind.STATUS, tags, dependency_ids)
	if not common_error.is_empty():
		return common_error
	var status_error := StableIdContract.validation_error(status_definition_id)
	if not status_error.is_empty():
		return status_error
	if duration_ticks <= 0 or stacks <= 0:
		return "Status effect duration and stacks must be positive."
	_publish_common(effect_id, Kind.STATUS, tags, dependency_ids)
	_status_definition_id = status_definition_id
	_duration_ticks = duration_ticks
	_stacks = stacks
	return ""


func configure_movement(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	movement_mode_id: String,
	distance: float,
	duration_ticks: int
) -> String:
	var common_error := _validate_common(effect_id, Kind.MOVEMENT, tags, dependency_ids)
	if not common_error.is_empty():
		return common_error
	var mode_error := StableIdContract.validation_error(movement_mode_id)
	if not mode_error.is_empty():
		return mode_error
	if not is_finite(distance) or distance < 0.0 or duration_ticks <= 0:
		return "Movement distance must be finite and non-negative, with positive duration."
	_publish_common(effect_id, Kind.MOVEMENT, tags, dependency_ids)
	_movement_mode_id = movement_mode_id
	_distance = distance
	_duration_ticks = duration_ticks
	return ""


func configure_projectile(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	projectile_definition_id: String,
	speed: float,
	lifetime_ticks: int
) -> String:
	var common_error := _validate_common(effect_id, Kind.PROJECTILE, tags, dependency_ids)
	if not common_error.is_empty():
		return common_error
	var projectile_error := StableIdContract.validation_error(projectile_definition_id)
	if not projectile_error.is_empty():
		return projectile_error
	if not is_finite(speed) or speed <= 0.0 or lifetime_ticks <= 0:
		return "Projectile speed and lifetime must be positive and finite."
	_publish_common(effect_id, Kind.PROJECTILE, tags, dependency_ids)
	_projectile_definition_id = projectile_definition_id
	_speed = speed
	_lifetime_ticks = lifetime_ticks
	return ""


func configure_persistent_entity(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	entity_definition_id: String,
	duration_ticks: int
) -> String:
	var common_error := _validate_common(
		effect_id,
		Kind.PERSISTENT_ENTITY,
		tags,
		dependency_ids
	)
	if not common_error.is_empty():
		return common_error
	var entity_error := StableIdContract.validation_error(entity_definition_id)
	if not entity_error.is_empty():
		return entity_error
	if duration_ticks <= 0:
		return "Persistent entity duration must be positive."
	_publish_common(effect_id, Kind.PERSISTENT_ENTITY, tags, dependency_ids)
	_entity_definition_id = entity_definition_id
	_duration_ticks = duration_ticks
	return ""


func configure_event(
	effect_id: String,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray,
	event_type: String,
	payload: Dictionary
) -> String:
	var common_error := _validate_common(effect_id, Kind.EVENT, tags, dependency_ids)
	if not common_error.is_empty():
		return common_error
	var validation_request := EventRequest.new()
	var event_error: String = validation_request.configure(
		event_type,
		1,
		0,
		effect_id,
		tags,
		payload
	)
	if not event_error.is_empty():
		return event_error
	_publish_common(effect_id, Kind.EVENT, tags, dependency_ids)
	_event_type = event_type
	_event_payload = payload.duplicate(true)
	return ""


func is_configured() -> bool:
	return _is_configured


func effect_id() -> String:
	return _effect_id


func kind() -> int:
	return _kind


func tags() -> PackedStringArray:
	return _tags.duplicate()


func dependency_ids() -> PackedStringArray:
	return _dependency_ids.duplicate()


func damage_components() -> Array:
	return _damage_components.duplicate()


func damage_modifiers() -> Array:
	return _damage_modifiers.duplicate()


func critical_chance_stat_id() -> String:
	return _critical_chance_stat_id


func critical_multiplier_stat_id() -> String:
	return _critical_multiplier_stat_id


func status_definition_id() -> String:
	return _status_definition_id


func duration_ticks() -> int:
	return _duration_ticks


func stacks() -> int:
	return _stacks


func movement_mode_id() -> String:
	return _movement_mode_id


func distance() -> float:
	return _distance


func projectile_definition_id() -> String:
	return _projectile_definition_id


func speed() -> float:
	return _speed


func lifetime_ticks() -> int:
	return _lifetime_ticks


func entity_definition_id() -> String:
	return _entity_definition_id


func event_type() -> String:
	return _event_type


func event_payload() -> Dictionary:
	return _event_payload.duplicate(true)


static func kind_name(kind_value: int) -> String:
	if kind_value < Kind.DAMAGE or kind_value > Kind.EVENT:
		return "UNKNOWN"
	return KIND_NAMES[kind_value]


func _validate_common(
	effect_id: String,
	kind_value: int,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray
) -> String:
	if _is_configured:
		return "Ability effect '%s' is already configured and immutable." % _effect_id
	var effect_error := StableIdContract.validation_error(effect_id)
	if not effect_error.is_empty():
		return effect_error
	if kind_value < Kind.DAMAGE or kind_value > Kind.EVENT:
		return "Unknown ability effect kind '%s'." % kind_value
	for values in [tags, dependency_ids]:
		var observed: Dictionary = {}
		for id_value in values:
			var id_error := StableIdContract.validation_error(id_value)
			if not id_error.is_empty():
				return id_error
			if observed.has(id_value):
				return "Ability effect '%s' repeats ID '%s'." % [effect_id, id_value]
			observed[id_value] = true
	if dependency_ids.has(effect_id):
		return "Ability effect '%s' cannot depend on itself." % effect_id
	return ""


func _publish_common(
	effect_id: String,
	kind_value: int,
	tags: PackedStringArray,
	dependency_ids: PackedStringArray
) -> void:
	_effect_id = effect_id
	_kind = kind_value
	_tags = tags.duplicate()
	_tags.sort()
	_dependency_ids = dependency_ids.duplicate()
	_dependency_ids.sort()
	_is_configured = true
