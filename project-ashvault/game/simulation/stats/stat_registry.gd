class_name StatRegistry
extends RefCounted

const StatDefinitionContract = preload("res://game/simulation/stats/stat_definition.gd")

var _definitions: Dictionary = {}
var _is_loaded := false


func load_definitions(definitions: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if _is_loaded:
		errors.append("Stat registry is already loaded and immutable.")
		return errors
	if definitions.is_empty():
		errors.append("Stat registry requires at least one definition.")
		return errors

	var staged: Dictionary = {}
	for index in definitions.size():
		var definition: Variant = definitions[index]
		if not definition is StatDefinitionContract:
			errors.append("Stat definition at index %d has an invalid type." % index)
			continue
		if not definition.is_configured():
			errors.append("Stat definition at index %d is not configured." % index)
			continue
		var key := StringName(definition.stat_id())
		if staged.has(key):
			errors.append("Duplicate stat ID '%s'." % definition.stat_id())
			continue
		staged[key] = definition

	if not errors.is_empty():
		errors.sort()
		return errors

	_definitions = staged
	_is_loaded = true
	return errors


func is_loaded() -> bool:
	return _is_loaded


func contains(stat_id: String) -> bool:
	return _is_loaded and _definitions.has(StringName(stat_id))


func get_definition(stat_id: String) -> RefCounted:
	if not _is_loaded:
		return null
	return _definitions.get(StringName(stat_id))


func ids() -> PackedStringArray:
	var result := PackedStringArray()
	if not _is_loaded:
		return result
	for stat_id: StringName in _definitions:
		result.append(String(stat_id))
	result.sort()
	return result
