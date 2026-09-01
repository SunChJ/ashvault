class_name TagRegistry
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _tags: Dictionary = {}
var _is_frozen := false


func register_tag(tag: String) -> String:
	if _is_frozen:
		return "Tag registry is frozen; cannot register '%s'." % tag

	var validation_error := StableIdContract.validation_error(tag)
	if not validation_error.is_empty():
		return "Invalid tag '%s': %s" % [tag, validation_error]

	var key := StringName(tag)
	if _tags.has(key):
		return "Tag '%s' is already registered." % tag

	_tags[key] = true
	return ""


func contains(tag: String) -> bool:
	return _tags.has(StringName(tag))


func validate_known(tags: Array[String]) -> PackedStringArray:
	var errors := PackedStringArray()
	for tag in tags:
		if not contains(tag):
			errors.append("Unknown tag '%s'." % tag)
	return errors


func all_tags() -> PackedStringArray:
	var result := PackedStringArray()
	for tag: StringName in _tags:
		result.append(String(tag))
	result.sort()
	return result


func freeze() -> void:
	_is_frozen = true


func is_frozen() -> bool:
	return _is_frozen
