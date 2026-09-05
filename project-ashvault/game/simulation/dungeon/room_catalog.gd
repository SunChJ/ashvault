class_name RoomCatalog
extends RefCounted

const Room = preload("res://game/simulation/dungeon/room_definition.gd")
const Catalog = preload("res://game/content/content_catalog.gd")
const Tags = preload("res://game/content/tag_registry.gd")

var _catalog := Catalog.new()


func load_definitions(definitions: Array) -> PackedStringArray:
	if definitions.is_empty() or definitions.size() > 512:
		return PackedStringArray(["Room catalogs require 1 to 512 authored definitions."])
	var errors := PackedStringArray()
	for definition: Variant in definitions:
		if not definition is Room:
			errors.append("Room catalog requires RoomDefinition Resources.")
			continue
		var error: String = definition.validation_error()
		if not error.is_empty():
			errors.append("%s: %s" % [definition.content_id, error])
	if not errors.is_empty():
		return errors
	return _catalog.load_definitions(definitions, Tags.new())


func is_loaded() -> bool:
	return _catalog.is_loaded()


func get_definition(id: String) -> Resource:
	return _catalog.get_definition(id)


func ids() -> PackedStringArray:
	return _catalog.ids()


func validation_report() -> Dictionary:
	if not is_loaded():
		return {}
	var rooms: Array = []
	for id: String in ids():
		rooms.append(get_definition(id).validation_metadata())
	return {"schema_version": 1, "rooms": rooms}
