class_name CombatEvent
extends RefCounted

const CORE_EVENT_TYPES: Array[String] = [
	"event.block",
	"event.cast",
	"event.critical",
	"event.damage",
	"event.death",
	"event.dodge",
	"event.hit",
	"event.item_dropped",
	"event.item_picked_up",
	"event.kill",
	"event.status_applied",
]

var _event_id := 0
var _chain_id := 0
var _depth := -1
var _event_type := ""
var _source_entity_id := 0
var _target_entity_id := 0
var _source_definition_id := ""
var _tags := PackedStringArray()
var _payload: Dictionary = {}
var _trigger_trace := PackedStringArray()
var _is_published := false


func event_id() -> int:
	return _event_id


func chain_id() -> int:
	return _chain_id


func depth() -> int:
	return _depth


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


func trigger_trace() -> PackedStringArray:
	return _trigger_trace.duplicate()


func _publish(
	event_id_value: int,
	chain_id_value: int,
	depth_value: int,
	request: RefCounted,
	trigger_trace_value: PackedStringArray
) -> String:
	if _is_published:
		return "Combat event %d is immutable after publication." % _event_id
	_event_id = event_id_value
	_chain_id = chain_id_value
	_depth = depth_value
	_event_type = request.event_type()
	_source_entity_id = request.source_entity_id()
	_target_entity_id = request.target_entity_id()
	_source_definition_id = request.source_definition_id()
	_tags = request.tags()
	_payload = request.payload()
	_trigger_trace = trigger_trace_value.duplicate()
	_is_published = true
	return ""
