class_name StatusChange
extends RefCounted

enum Outcome {
	APPLIED,
	STACKED,
	REFRESHED,
	UNCHANGED,
	IMMUNE,
	TARGET_UNAVAILABLE,
	CLEANSED,
	PROTECTED,
	REMOVED,
	MISSING,
	EXPIRED,
}

const OUTCOME_NAMES: Array[String] = [
	"APPLIED",
	"STACKED",
	"REFRESHED",
	"UNCHANGED",
	"IMMUNE",
	"TARGET_UNAVAILABLE",
	"CLEANSED",
	"PROTECTED",
	"REMOVED",
	"MISSING",
	"EXPIRED",
]

var _tick := -1
var _mutation_id := 0
var _status_id := ""
var _source_entity_id := 0
var _target_entity_id := 0
var _outcome := -1
var _previous_stacks := 0
var _current_stacks := 0
var _previous_expiry_tick := -1
var _current_expiry_tick := -1
var _is_configured := false


func tick() -> int:
	return _tick


func mutation_id() -> int:
	return _mutation_id


func status_id() -> String:
	return _status_id


func source_entity_id() -> int:
	return _source_entity_id


func target_entity_id() -> int:
	return _target_entity_id


func outcome() -> int:
	return _outcome


func previous_stacks() -> int:
	return _previous_stacks


func current_stacks() -> int:
	return _current_stacks


func previous_expiry_tick() -> int:
	return _previous_expiry_tick


func current_expiry_tick() -> int:
	return _current_expiry_tick


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		_tick,
		_mutation_id,
		_status_id,
		_source_entity_id,
		_target_entity_id,
		_outcome,
		_previous_stacks,
		_current_stacks,
		_previous_expiry_tick,
		_current_expiry_tick,
	]


func _configure(
	tick_value: int,
	mutation_id_value: int,
	status_id_value: String,
	source_entity_id_value: int,
	target_entity_id_value: int,
	outcome_value: int,
	previous_stacks_value: int,
	current_stacks_value: int,
	previous_expiry_tick_value: int,
	current_expiry_tick_value: int
) -> void:
	if _is_configured:
		return
	_tick = tick_value
	_mutation_id = mutation_id_value
	_status_id = status_id_value
	_source_entity_id = source_entity_id_value
	_target_entity_id = target_entity_id_value
	_outcome = outcome_value
	_previous_stacks = previous_stacks_value
	_current_stacks = current_stacks_value
	_previous_expiry_tick = previous_expiry_tick_value
	_current_expiry_tick = current_expiry_tick_value
	_is_configured = true


static func outcome_name(value: int) -> String:
	if value < Outcome.APPLIED or value > Outcome.EXPIRED:
		return "UNKNOWN"
	return OUTCOME_NAMES[value]
