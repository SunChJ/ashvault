class_name StatusDefinition
extends Resource

const ModifierTemplateContract = preload(
	"res://game/simulation/statuses/status_damage_modifier_template.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

enum StackPolicy {
	ADD,
	REPLACE,
	MAXIMUM,
}

enum RefreshPolicy {
	KEEP,
	RESET,
	EXTEND,
}

enum RemovalPolicy {
	CLEANSABLE,
	PROTECTED,
}

const SCHEMA_VERSION := 1

var _status_id := ""
var _tags := PackedStringArray()
var _minimum_duration_ticks := 0
var _maximum_duration_ticks := 0
var _max_stacks := 0
var _stack_policy := -1
var _refresh_policy := -1
var _removal_policy := -1
var _damage_modifier_templates: Array = []
var _is_configured := false


func configure(
	status_id_value: String,
	tags_value: PackedStringArray,
	minimum_duration_ticks_value: int,
	maximum_duration_ticks_value: int,
	max_stacks_value: int,
	stack_policy_value: int,
	refresh_policy_value: int,
	removal_policy_value: int,
	damage_modifier_templates_value: Array
) -> String:
	if _is_configured:
		return "Status definition '%s' is immutable." % _status_id
	var id_error := StableIdContract.validation_error(status_id_value)
	if not id_error.is_empty():
		return id_error
	var tag_error := _validate_tags(tags_value)
	if not tag_error.is_empty():
		return tag_error
	if (
		minimum_duration_ticks_value <= 0
		or maximum_duration_ticks_value < minimum_duration_ticks_value
	):
		return "Status duration bounds must be positive and ordered."
	if max_stacks_value <= 0:
		return "Status maximum stacks must be positive."
	if stack_policy_value < StackPolicy.ADD or stack_policy_value > StackPolicy.MAXIMUM:
		return "Unknown status stack policy '%d'." % stack_policy_value
	if refresh_policy_value < RefreshPolicy.KEEP or refresh_policy_value > RefreshPolicy.EXTEND:
		return "Unknown status refresh policy '%d'." % refresh_policy_value
	if removal_policy_value < RemovalPolicy.CLEANSABLE or removal_policy_value > RemovalPolicy.PROTECTED:
		return "Unknown status removal policy '%d'." % removal_policy_value
	var modifier_error := _validate_modifier_templates(damage_modifier_templates_value)
	if not modifier_error.is_empty():
		return modifier_error

	_status_id = status_id_value
	_tags = tags_value.duplicate()
	_tags.sort()
	_minimum_duration_ticks = minimum_duration_ticks_value
	_maximum_duration_ticks = maximum_duration_ticks_value
	_max_stacks = max_stacks_value
	_stack_policy = stack_policy_value
	_refresh_policy = refresh_policy_value
	_removal_policy = removal_policy_value
	_damage_modifier_templates = damage_modifier_templates_value.duplicate()
	_damage_modifier_templates.sort_custom(_modifier_precedes)
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func status_id() -> String:
	return _status_id


func tags() -> PackedStringArray:
	return _tags.duplicate()


func max_stacks() -> int:
	return _max_stacks


func stack_policy() -> int:
	return _stack_policy


func refresh_policy() -> int:
	return _refresh_policy


func removal_policy() -> int:
	return _removal_policy


func accepts_duration(duration_ticks: int) -> bool:
	return (
		duration_ticks >= _minimum_duration_ticks
		and duration_ticks <= _maximum_duration_ticks
	)


func damage_modifiers(stack_count: int) -> Array:
	var result: Array = []
	for template: Resource in _damage_modifier_templates:
		result.append(template._instantiate(_status_id, stack_count))
	return result


func canonical_values() -> Array:
	if not _is_configured:
		return []
	var modifier_values: Array = []
	for template: Resource in _damage_modifier_templates:
		modifier_values.append(template.canonical_values())
	return [
		SCHEMA_VERSION,
		_status_id,
		Array(_tags),
		_minimum_duration_ticks,
		_maximum_duration_ticks,
		_max_stacks,
		_stack_policy,
		_refresh_policy,
		_removal_policy,
		modifier_values,
	]


static func _validate_tags(values: PackedStringArray) -> String:
	var observed: Dictionary = {}
	for value in values:
		var error := StableIdContract.validation_error(value)
		if not error.is_empty():
			return "Invalid status tag: %s" % error
		if observed.has(value):
			return "Duplicate status tag '%s'." % value
		observed[value] = true
	return ""


static func _validate_modifier_templates(values: Array) -> String:
	var observed: Dictionary = {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is ModifierTemplateContract or not value.is_configured():
			return "Status damage modifier template at index %d is not configured." % index
		var identity: String = value.identity_key()
		if observed.has(identity):
			return "Duplicate status damage modifier template '%s'." % identity
		observed[identity] = true
	return ""


static func _modifier_precedes(left: Resource, right: Resource) -> bool:
	return left.identity_key() < right.identity_key()
