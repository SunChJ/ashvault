class_name DeliveryHit
extends RefCounted

var _tick := -1
var _request_id := 0
var _runtime_id := 0
var _definition_id := ""
var _kind := -1
var _source_entity_id := 0
var _target_entity_id := 0
var _impact_position := Vector2.ZERO
var _ordinal := -1
var _is_configured := false


func tick() -> int:
	return _tick


func request_id() -> int:
	return _request_id


func runtime_id() -> int:
	return _runtime_id


func definition_id() -> String:
	return _definition_id


func kind() -> int:
	return _kind


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func impact_position() -> Vector2:
	return _impact_position


func ordinal() -> int:
	return _ordinal


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_tick,
		_request_id,
		_runtime_id,
		_definition_id,
		_kind,
		_source_entity_id,
		_target_entity_id,
		_impact_position.x,
		_impact_position.y,
		_ordinal,
	]


func _configure(
	tick_value: int,
	request_id_value: int,
	runtime_id_value: int,
	definition_id_value: String,
	kind_value: int,
	source_entity_id_value: int,
	target_entity_id_value: int,
	impact_position_value: Vector2,
	ordinal_value: int
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_request_id = request_id_value
	_runtime_id = runtime_id_value
	_definition_id = definition_id_value
	_kind = kind_value
	_source_entity_id = source_entity_id_value
	_target_entity_id = target_entity_id_value
	_impact_position = impact_position_value
	_ordinal = ordinal_value
	_is_configured = true
