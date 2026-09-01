class_name DamageComponent
extends RefCounted

const StableIdContract = preload("res://game/content/stable_id.gd")

var _damage_type_id := ""
var _amount := 0.0
var _source_id := ""
var _is_configured := false


func configure(damage_type_id: String, amount: float, source_id: String) -> String:
	if _is_configured:
		return "Damage component from '%s' is already configured and immutable." % _source_id
	for id_value in [damage_type_id, source_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not is_finite(amount) or amount < 0.0:
		return "Base damage from '%s' must be finite and non-negative." % source_id

	_damage_type_id = damage_type_id
	_amount = amount
	_source_id = source_id
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func damage_type_id() -> String:
	return _damage_type_id


func amount() -> float:
	return _amount


func source_id() -> String:
	return _source_id
