class_name StatSnapshot
extends RefCounted

var _tick := -1
var _values: Dictionary = {}
var _explanations: Dictionary = {}
var _is_configured := false


func tick() -> int:
	return _tick


func has_stat(stat_id: String) -> bool:
	return _values.has(StringName(stat_id))


func value(stat_id: String) -> float:
	if not has_stat(stat_id):
		return NAN
	return _values[StringName(stat_id)]


func values() -> Dictionary:
	var result: Dictionary = {}
	for stat_id: StringName in _values:
		result[String(stat_id)] = _values[stat_id]
	return result


func explanation(stat_id: String) -> Dictionary:
	if not has_stat(stat_id):
		return {}
	return _explanations[StringName(stat_id)].duplicate(true)


func _configure(
	tick_value: int,
	values_value: Dictionary,
	explanations: Dictionary
) -> String:
	if _is_configured:
		return "Stat snapshot is immutable after publication."
	_tick = tick_value
	_values = values_value.duplicate(true)
	_explanations = explanations.duplicate(true)
	_is_configured = true
	return ""
