class_name TagRegistry
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _tags: Dictionary = {}
var _is_frozen := false


func register_tag(tag: String) -> String:
	var errors := register_tags([tag])
	return "" if errors.is_empty() else errors[0]


func register_tags(tags: Array[String]) -> PackedStringArray:
	var errors := PackedStringArray()
	if _is_frozen:
		errors.append("Tag registry is frozen; cannot register tags.")
		return errors

	var pending: Dictionary = {}
	for tag in tags:
		var validation_error := StableIdContract.validation_error(tag)
		if not validation_error.is_empty():
			errors.append("Invalid tag '%s': %s" % [tag, validation_error])
			continue

		var key := StringName(tag)
		if _tags.has(key) or pending.has(key):
			errors.append("Tag '%s' is already registered." % tag)
			continue
		pending[key] = true

	if not errors.is_empty():
		return errors

	for key: StringName in pending:
		_tags[key] = true
	return errors


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
