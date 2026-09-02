class_name StatusRemoval
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

enum Reason {
	CLEANSE,
	FORCED,
}

var _mutation_id := 0
var _source_entity_id := 0
var _target_entity_id := 0
var _status_id := ""
var _reason := -1
var _is_configured := false


func configure(
	mutation_id_value: int,
	source_entity_id_value: int,
	target_entity_id_value: int,
	status_id_value: String,
	reason_value: int
) -> String:
	if _is_configured:
		return "Status removal %d is immutable." % _mutation_id
	if mutation_id_value <= 0:
		return "Status mutation ID must be positive."
	if source_entity_id_value <= 0 or target_entity_id_value <= 0:
		return "Status removal entity IDs must be positive."
	var status_error := StableIdContract.validation_error(status_id_value)
	if not status_error.is_empty():
		return status_error
	if reason_value < Reason.CLEANSE or reason_value > Reason.FORCED:
		return "Unknown status removal reason '%d'." % reason_value
	_mutation_id = mutation_id_value
	_source_entity_id = source_entity_id_value
	_target_entity_id = target_entity_id_value
	_status_id = status_id_value
	_reason = reason_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func mutation_id() -> int:
	return _mutation_id


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func status_id() -> String:
	return _status_id


func reason() -> int:
	return _reason
