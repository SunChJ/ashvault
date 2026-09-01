class_name CombatEventRequest
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")
const MAX_PAYLOAD_DEPTH := 32

var _event_type := ""
var _source_entity_id := 0
var _target_entity_id := 0
var _source_definition_id := ""
var _tags := PackedStringArray()
var _payload: Dictionary = {}
var _is_configured := false


func configure(
	event_type: String,
	source_entity_id: int,
	target_entity_id: int,
	source_definition_id: String,
	tags: PackedStringArray,
	payload: Dictionary
) -> String:
	if _is_configured:
		return "Combat event request '%s' is already configured and immutable." % _event_type
	for id_value in [event_type, source_definition_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if source_entity_id <= 0:
		return "Combat event source entity ID must be positive."
	if target_entity_id < 0:
		return "Combat event target entity ID must be zero or positive."
	var tag_error := _validate_tags(tags)
	if not tag_error.is_empty():
		return tag_error
	var payload_error := _validate_payload(payload, 0, "payload")
	if not payload_error.is_empty():
		return payload_error

	_event_type = event_type
	_source_entity_id = source_entity_id
	_target_entity_id = target_entity_id
	_source_definition_id = source_definition_id
	_tags = tags.duplicate()
	_tags.sort()
	_payload = payload.duplicate(true)
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func event_type() -> String:
	return _event_type


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func source_definition_id() -> String:
	return _source_definition_id


func tags() -> PackedStringArray:
	return _tags.duplicate()


func payload() -> Dictionary:
	return _payload.duplicate(true)


static func _validate_tags(tags: PackedStringArray) -> String:
	var observed: Dictionary = {}
	for tag in tags:
		var tag_error := StableIdContract.validation_error(tag)
		if not tag_error.is_empty():
			return "Invalid combat event tag: %s" % tag_error
		if observed.has(tag):
			return "Duplicate combat event tag '%s'." % tag
		observed[tag] = true
	return ""


static func _validate_payload(value: Variant, depth: int, path: String) -> String:
	if depth > MAX_PAYLOAD_DEPTH:
		return "Combat event payload exceeds maximum nesting depth at '%s'." % path
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			if not is_finite(value):
				return "Combat event payload float at '%s' must be finite." % path
			return ""
		TYPE_ARRAY:
			for index in value.size():
				var item_error := _validate_payload(
					value[index],
					depth + 1,
					"%s[%d]" % [path, index]
				)
				if not item_error.is_empty():
					return item_error
			return ""
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String:
					return "Combat event payload keys must be strings at '%s'." % path
				var field_error := _validate_payload(
					value[key],
					depth + 1,
					"%s.%s" % [path, key]
				)
				if not field_error.is_empty():
					return field_error
			return ""
	return "Combat event payload at '%s' must contain only finite JSON-compatible values." % path
