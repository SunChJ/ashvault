class_name StatusDamageModifierTemplate
extends Resource

const DamageModifierContract = preload(
	"res://game/simulation/combat/damage_modifier.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

const SCHEMA_VERSION := 1

var _damage_type_id := ""
var _amount_per_stack := 0.0
var _source_id := ""
var _priority := 0
var _is_configured := false


func configure(
	damage_type_id_value: String,
	amount_per_stack_value: float,
	source_id_value: String,
	priority_value: int = 0
) -> String:
	if _is_configured:
		return "Status damage modifier template '%s' is immutable." % _source_id
	for id_value in [damage_type_id_value, source_id_value]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not is_finite(amount_per_stack_value):
		return "Status damage modifier amount per stack must be finite."
	_damage_type_id = damage_type_id_value
	_amount_per_stack = amount_per_stack_value
	_source_id = source_id_value
	_priority = priority_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func identity_key() -> String:
	return "%s|%s" % [_damage_type_id, _source_id]


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		SCHEMA_VERSION,
		_damage_type_id,
		_amount_per_stack,
		_source_id,
		_priority,
	]


func _instantiate(status_id: String, stack_count: int) -> RefCounted:
	var modifier := DamageModifierContract.new()
	var error: String = modifier.configure(
		_damage_type_id,
		DamageModifierContract.Operation.CONDITIONAL,
		_amount_per_stack * float(stack_count),
		_source_id,
		"",
		status_id,
		_priority
	)
	assert(error.is_empty())
	return modifier
