class_name StatusRuntimeState
extends RefCounted

var _target_entity_id := 0
var _status_id := ""
var _source_entity_id := 0
var _stack_count := 0
var _expiry_tick := -1
var _last_mutation_id := 0
var _is_configured := false


func target_entity_id() -> int:
	return _target_entity_id


func status_id() -> String:
	return _status_id


func source_entity_id() -> int:
	return _source_entity_id


func stack_count() -> int:
	return _stack_count


func expiry_tick() -> int:
	return _expiry_tick


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_target_entity_id,
		_status_id,
		_source_entity_id,
		_stack_count,
		_expiry_tick,
		_last_mutation_id,
	]


func _configure(
	target_entity_id_value: int,
	status_id_value: String,
	source_entity_id_value: int,
	stack_count_value: int,
	expiry_tick_value: int,
	mutation_id_value: int
) -> void:
	if _is_configured:
		return
	_target_entity_id = target_entity_id_value
	_status_id = status_id_value
	_apply(source_entity_id_value, stack_count_value, expiry_tick_value, mutation_id_value)
	_is_configured = true


func _apply(
	source_entity_id_value: int,
	stack_count_value: int,
	expiry_tick_value: int,
	mutation_id_value: int
) -> void:
	_source_entity_id = source_entity_id_value
	_stack_count = stack_count_value
	_expiry_tick = expiry_tick_value
	_last_mutation_id = mutation_id_value


func _duplicate_state() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._target_entity_id = _target_entity_id
	result._status_id = _status_id
	result._source_entity_id = _source_entity_id
	result._stack_count = _stack_count
	result._expiry_tick = _expiry_tick
	result._last_mutation_id = _last_mutation_id
	result._is_configured = _is_configured
	return result
