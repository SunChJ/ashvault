class_name AbilityLoadout
extends RefCounted

const BindingContract = preload(
	"res://game/simulation/abilities/ability_cast_binding.gd"
)
const StableIdContract = preload("res://game/content/stable_id.gd")

var _resource_id := ""
var _bindings: Dictionary = {}
var _is_configured := false


func configure(resource_id_value: String, bindings_value: Array) -> String:
	if _is_configured:
		return "Ability loadout is immutable after configuration."
	var resource_error := StableIdContract.validation_error(resource_id_value)
	if not resource_error.is_empty():
		return resource_error
	if bindings_value.is_empty():
		return "Ability loadout requires at least one cast binding."

	var staged_bindings: Dictionary = {}
	for value: Variant in bindings_value:
		if not value is BindingContract or not value.is_configured():
			return "Ability loadout values must be configured AbilityCastBinding instances."
		var slot: int = value.ability_slot()
		if staged_bindings.has(slot):
			return "Duplicate ability loadout slot %d." % slot
		var cost_resource_id: String = value.ability().cost_resource_id()
		if not cost_resource_id.is_empty() and cost_resource_id != resource_id_value:
			return "Ability slot %d consumes '%s', not loadout resource '%s'." % [
				slot,
				cost_resource_id,
				resource_id_value,
			]
		staged_bindings[slot] = value

	_resource_id = resource_id_value
	_bindings = staged_bindings
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func resource_id() -> String:
	return _resource_id


func has_slot(ability_slot: int) -> bool:
	return _bindings.has(ability_slot)


func binding(ability_slot: int) -> RefCounted:
	return _bindings.get(ability_slot)


func slots() -> Array:
	var result: Array = _bindings.keys()
	result.sort()
	return result


func canonical_values() -> Array:
	if not _is_configured:
		return []
	var binding_values: Array = []
	for slot: int in slots():
		binding_values.append(_bindings[slot].canonical_values())
	return [_resource_id, binding_values]


func _duplicate_value() -> RefCounted:
	var bindings: Array = []
	for slot: int in slots():
		bindings.append(_bindings[slot])
	var result: RefCounted = get_script().new()
	var error: String = result.configure(_resource_id, bindings)
	assert(error.is_empty(), "Configured ability loadouts must be duplicable.")
	return result
