class_name StatDefinition
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _stat_id := ""
var _default_value := 0.0
var _is_configured := false


func configure(stat_id: String, default_value: float) -> String:
	if _is_configured:
		return "Stat definition '%s' is already configured and immutable." % _stat_id
	var id_error := StableIdContract.validation_error(stat_id)
	if not id_error.is_empty():
		return id_error
	if not is_finite(default_value):
		return "Default value for stat '%s' must be finite." % stat_id

	_stat_id = stat_id
	_default_value = default_value
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func stat_id() -> String:
	return _stat_id


func default_value() -> float:
	return _default_value
