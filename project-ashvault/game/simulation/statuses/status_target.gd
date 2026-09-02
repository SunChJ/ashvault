class_name StatusTarget
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _entity_id := 0
var _is_alive := false
var _immune_status_ids := PackedStringArray()
var _immune_tags := PackedStringArray()
var _is_configured := false


func configure(
	entity_id_value: int,
	is_alive_value: bool,
	immune_status_ids_value: PackedStringArray = PackedStringArray(),
	immune_tags_value: PackedStringArray = PackedStringArray()
) -> String:
	if _is_configured:
		return "Status target %d is immutable." % _entity_id
	if entity_id_value <= 0:
		return "Status target entity ID must be positive."
	var status_error := _validate_ids(immune_status_ids_value, "immune status")
	if not status_error.is_empty():
		return status_error
	var tag_error := _validate_ids(immune_tags_value, "immune tag")
	if not tag_error.is_empty():
		return tag_error
	_entity_id = entity_id_value
	_is_alive = is_alive_value
	_immune_status_ids = immune_status_ids_value.duplicate()
	_immune_status_ids.sort()
	_immune_tags = immune_tags_value.duplicate()
	_immune_tags.sort()
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func entity_id() -> int:
	return _entity_id


func is_alive() -> bool:
	return _is_alive


func is_immune_to(definition: Resource) -> bool:
	if _immune_status_ids.has(definition.status_id()):
		return true
	for tag in definition.tags():
		if _immune_tags.has(tag):
			return true
	return false


static func _validate_ids(values: PackedStringArray, label: String) -> String:
	var observed: Dictionary = {}
	for value in values:
		var error := StableIdContract.validation_error(value)
		if not error.is_empty():
			return "Invalid %s: %s" % [label, error]
		if observed.has(value):
			return "Duplicate %s '%s'." % [label, value]
		observed[value] = true
	return ""
