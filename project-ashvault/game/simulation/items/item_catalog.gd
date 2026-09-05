class_name ItemCatalog
extends RefCounted

const Definition = preload("res://game/simulation/items/item_definition.gd")
const Catalog = preload("res://game/content/content_catalog.gd")

var _catalog := Catalog.new()


func load_definitions(definitions: Array, tag_registry: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	for definition: Variant in definitions:
		if not definition is Definition:
			errors.append("Item catalog accepts only ItemDefinition Resources.")
		else:
			var error: String = definition.validation_error()
			if not error.is_empty():
				errors.append(error)
	if not errors.is_empty():
		return errors
	return _catalog.load_definitions(definitions, tag_registry)


func is_loaded() -> bool:
	return _catalog.is_loaded()


func get_definition(content_id: String) -> Resource:
	return _catalog.get_definition(content_id)


func ids() -> PackedStringArray:
	return _catalog.ids()
