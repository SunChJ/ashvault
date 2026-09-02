class_name StatusApplication
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _mutation_id := 0
var _status_id := ""
var _source_entity_id := 0
var _target_entity_id := 0
var _duration_ticks := 0
var _stacks := 0
var _is_configured := false


func configure(
	mutation_id_value: int,
	status_id_value: String,
	source_entity_id_value: int,
	target_entity_id_value: int,
	duration_ticks_value: int,
	stacks_value: int
) -> String:
	if _is_configured:
		return "Status application %d is immutable." % _mutation_id
	if mutation_id_value <= 0:
		return "Status mutation ID must be positive."
	var status_error := StableIdContract.validation_error(status_id_value)
	if not status_error.is_empty():
		return status_error
	if source_entity_id_value <= 0 or target_entity_id_value <= 0:
		return "Status application entity IDs must be positive."
	if duration_ticks_value <= 0 or stacks_value <= 0:
		return "Status application duration and stacks must be positive."
	_mutation_id = mutation_id_value
	_status_id = status_id_value
	_source_entity_id = source_entity_id_value
	_target_entity_id = target_entity_id_value
	_duration_ticks = duration_ticks_value
	_stacks = stacks_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func mutation_id() -> int:
	return _mutation_id


func status_id() -> String:
	return _status_id


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func duration_ticks() -> int:
	return _duration_ticks


func stacks() -> int:
	return _stacks
