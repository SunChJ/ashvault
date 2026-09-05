class_name ItemCatalog
extends RefCounted

const Definition = preload("res://game/simulation/items/item_definition.gd")
const Affixes = preload("res://game/simulation/items/affix_catalog.gd")
const Rules = preload("res://game/simulation/items/rarity_rules.gd")
const Crafting = preload("res://game/simulation/items/crafting_catalog.gd")
const Catalog = preload("res://game/content/content_catalog.gd")

var _catalog := Catalog.new()
var _affixes: RefCounted
var _crafting: RefCounted


func load_definitions(definitions: Array, tag_registry: Variant, affix_catalog: Variant = null, crafting_catalog: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	var staged_crafting: Variant = crafting_catalog
	if staged_crafting == null:
		staged_crafting = Crafting.new()
		staged_crafting.load_definitions([], [])
	if not staged_crafting is Crafting or not staged_crafting.is_loaded():
		return PackedStringArray(["Item catalog requires published crafting definitions."])
	var staged_affixes: Variant = affix_catalog
	if staged_affixes == null:
		staged_affixes = Affixes.new()
		staged_affixes.load_definitions([])
	if not staged_affixes is Affixes or not staged_affixes.is_loaded():
		return PackedStringArray(["Item catalog requires a published AffixCatalog."])
	for definition: Variant in definitions:
		if not definition is Definition:
			errors.append("Item catalog accepts only ItemDefinition Resources.")
		else:
			var error: String = definition.validation_error()
			if error.is_empty():
				error = Rules.definition_error(definition, staged_affixes)
			if not error.is_empty():
				errors.append(error)
	if not errors.is_empty():
		return errors
	var known_items: Dictionary = {}
	for definition: Resource in definitions:
		known_items[definition.content_id] = definition
	var crafting_error: String = staged_crafting.bases_error(known_items)
	if not crafting_error.is_empty():
		errors.append(crafting_error)
	for id: String in staged_affixes.ids():
		for base_id: String in staged_affixes.get_definition(id).allowed_bases:
			if not known_items.has(base_id):
				errors.append("Affix '%s' references unknown base '%s'." % [id, base_id])
	if not errors.is_empty():
		return errors
	errors = _catalog.load_definitions(definitions, tag_registry)
	if errors.is_empty():
		_affixes = staged_affixes
		_crafting = staged_crafting
	return errors


func is_loaded() -> bool:
	return _catalog.is_loaded()


func get_definition(content_id: String) -> Resource:
	return _catalog.get_definition(content_id)


func ids() -> PackedStringArray:
	return _catalog.ids()


func affix_catalog() -> RefCounted:
	return _affixes


func validate_record(record: Dictionary) -> String:
	if not record.get("definition_id") is String:
		return "Item record requires a definition ID."
	var definition: Resource = get_definition(record.definition_id)
	if definition == null:
		return "Item record references an unknown definition."
	var error: String = Rules.record_error(record, definition, _affixes)
	return _crafting.record_error(record) if error.is_empty() else error


func crafting_catalog() -> RefCounted:
	return _crafting
