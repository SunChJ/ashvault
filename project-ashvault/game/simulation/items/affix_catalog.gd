class_name AffixCatalog
extends RefCounted

const Definition = preload("res://game/simulation/items/affix_definition.gd")
const Catalog = preload("res://game/content/content_catalog.gd")
const Tags = preload("res://game/content/tag_registry.gd")

var _catalog := Catalog.new()


func load_definitions(definitions: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if definitions.size() > 128:
		return PackedStringArray(["Affix catalog exceeds 128 definitions."])
	var ids_seen: Dictionary = {}
	for definition: Variant in definitions:
		if not definition is Definition:
			errors.append("Affix catalog accepts AffixDefinition Resources only.")
			continue
		var error: String = definition.validation_error()
		if not error.is_empty():
			errors.append(error)
		ids_seen[definition.content_id] = true
	if not errors.is_empty():
		return errors
	for definition: Resource in definitions:
		for excluded: String in definition.excluded_affixes:
			if not ids_seen.has(excluded):
				errors.append("Unknown excluded affix '%s'." % excluded)
	if not errors.is_empty():
		return errors
	return _catalog.load_definitions(definitions, Tags.new())


func is_loaded() -> bool:
	return _catalog.is_loaded()


func get_definition(id: String) -> Resource:
	return _catalog.get_definition(id)


func ids() -> PackedStringArray:
	return _catalog.ids()
