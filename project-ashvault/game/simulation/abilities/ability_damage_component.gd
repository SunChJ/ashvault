class_name AbilityDamageComponent
extends Resource

const StableIdContract = preload("res://game/content/stable_id.gd")

var _damage_type_id := ""
var _base_amount := 0.0
var _scaling_stat_id := ""
var _scaling_coefficient := 0.0
var _source_id := ""
var _is_configured := false


func configure(
	damage_type_id: String,
	base_amount: float,
	scaling_stat_id: String,
	scaling_coefficient: float,
	source_id: String
) -> String:
	if _is_configured:
		return "Ability damage component from '%s' is already configured and immutable." % _source_id
	for id_value in [damage_type_id, source_id]:
		var id_error := StableIdContract.validation_error(id_value)
		if not id_error.is_empty():
			return id_error
	if not is_finite(base_amount) or base_amount < 0.0:
		return "Ability base damage must be finite and non-negative."
	if not is_finite(scaling_coefficient) or scaling_coefficient < 0.0:
		return "Ability damage scaling coefficient must be finite and non-negative."
	if scaling_stat_id.is_empty() and scaling_coefficient != 0.0:
		return "Ability damage scaling requires a stable stat ID."
	if not scaling_stat_id.is_empty():
		var stat_error := StableIdContract.validation_error(scaling_stat_id)
		if not stat_error.is_empty():
			return stat_error

	_damage_type_id = damage_type_id
	_base_amount = base_amount
	_scaling_stat_id = scaling_stat_id
	_scaling_coefficient = scaling_coefficient
	_source_id = source_id
	_is_configured = true
	return ""


func is_configured() -> bool:
	return _is_configured


func damage_type_id() -> String:
	return _damage_type_id


func base_amount() -> float:
	return _base_amount


func scaling_stat_id() -> String:
	return _scaling_stat_id


func scaling_coefficient() -> float:
	return _scaling_coefficient


func source_id() -> String:
	return _source_id


func identity_key() -> String:
	return "%s|%s|%s" % [_damage_type_id, _source_id, _scaling_stat_id]
