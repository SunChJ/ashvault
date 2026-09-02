class_name DeliveryDefinition
extends Resource

const StableIdContract = preload("res://game/content/stable_id.gd")

enum Kind {
	PROJECTILE,
	AREA,
	CHAIN,
	PERSISTENT,
}

const SCHEMA_VERSION := 1

var _definition_id := ""
var _kind := -1
var _radius := 0.0
var _speed_per_second := 0.0
var _lifetime_ticks := 0
var _max_targets := 0
var _acquisition_range := 0.0
var _chain_range := 0.0
var _pulse_interval_ticks := 0
var _is_configured := false


func configure_projectile(
	definition_id_value: String,
	radius_value: float,
	speed_per_second_value: float,
	lifetime_ticks_value: int,
	max_targets_value: int
) -> String:
	var common_error := _validate_common(definition_id_value)
	if not common_error.is_empty():
		return common_error
	if not _is_non_negative_finite(radius_value):
		return "Projectile radius must be finite and non-negative."
	if not is_finite(speed_per_second_value) or speed_per_second_value <= 0.0:
		return "Projectile speed must be finite and positive."
	if lifetime_ticks_value <= 0 or max_targets_value <= 0:
		return "Projectile lifetime and target limit must be positive."
	_publish(
		definition_id_value,
		Kind.PROJECTILE,
		radius_value,
		speed_per_second_value,
		lifetime_ticks_value,
		max_targets_value,
		0.0,
		0.0,
		0
	)
	return ""


func configure_area(
	definition_id_value: String,
	radius_value: float,
	max_targets_value: int
) -> String:
	var common_error := _validate_common(definition_id_value)
	if not common_error.is_empty():
		return common_error
	if not _is_non_negative_finite(radius_value):
		return "Area radius must be finite and non-negative."
	if max_targets_value < 0:
		return "Area target limit must be non-negative."
	_publish(
		definition_id_value,
		Kind.AREA,
		radius_value,
		0.0,
		0,
		max_targets_value,
		0.0,
		0.0,
		0
	)
	return ""


func configure_chain(
	definition_id_value: String,
	acquisition_range_value: float,
	chain_range_value: float,
	max_targets_value: int
) -> String:
	var common_error := _validate_common(definition_id_value)
	if not common_error.is_empty():
		return common_error
	if (
		not is_finite(acquisition_range_value)
		or acquisition_range_value <= 0.0
		or not is_finite(chain_range_value)
		or chain_range_value <= 0.0
		or max_targets_value <= 0
	):
		return "Chain acquisition range, jump range, and target limit must be positive."
	_publish(
		definition_id_value,
		Kind.CHAIN,
		0.0,
		0.0,
		0,
		max_targets_value,
		acquisition_range_value,
		chain_range_value,
		0
	)
	return ""


func configure_persistent(
	definition_id_value: String,
	radius_value: float,
	lifetime_ticks_value: int,
	pulse_interval_ticks_value: int,
	max_targets_value: int
) -> String:
	var common_error := _validate_common(definition_id_value)
	if not common_error.is_empty():
		return common_error
	if not _is_non_negative_finite(radius_value):
		return "Persistent radius must be finite and non-negative."
	if lifetime_ticks_value <= 0 or pulse_interval_ticks_value <= 0:
		return "Persistent lifetime and pulse interval must be positive."
	if max_targets_value < 0:
		return "Persistent target limit must be non-negative."
	_publish(
		definition_id_value,
		Kind.PERSISTENT,
		radius_value,
		0.0,
		lifetime_ticks_value,
		max_targets_value,
		0.0,
		0.0,
		pulse_interval_ticks_value
	)
	return ""


func is_configured() -> bool:
	return _is_configured


func definition_id() -> String:
	return _definition_id


func kind() -> int:
	return _kind


func radius() -> float:
	return _radius


func speed_per_second() -> float:
	return _speed_per_second


func lifetime_ticks() -> int:
	return _lifetime_ticks


func max_targets() -> int:
	return _max_targets


func acquisition_range() -> float:
	return _acquisition_range


func chain_range() -> float:
	return _chain_range


func pulse_interval_ticks() -> int:
	return _pulse_interval_ticks


func canonical_values() -> Array:
	if not _is_configured:
		return []
	return [
		SCHEMA_VERSION,
		_definition_id,
		_kind,
		_radius,
		_speed_per_second,
		_lifetime_ticks,
		_max_targets,
		_acquisition_range,
		_chain_range,
		_pulse_interval_ticks,
	]


func _validate_common(definition_id_value: String) -> String:
	if _is_configured:
		return "Delivery definition '%s' is immutable." % _definition_id
	return StableIdContract.validation_error(definition_id_value)


func _publish(
	definition_id_value: String,
	kind_value: int,
	radius_value: float,
	speed_per_second_value: float,
	lifetime_ticks_value: int,
	max_targets_value: int,
	acquisition_range_value: float,
	chain_range_value: float,
	pulse_interval_ticks_value: int
) -> void:
	_definition_id = definition_id_value
	_kind = kind_value
	_radius = radius_value
	_speed_per_second = speed_per_second_value
	_lifetime_ticks = lifetime_ticks_value
	_max_targets = max_targets_value
	_acquisition_range = acquisition_range_value
	_chain_range = chain_range_value
	_pulse_interval_ticks = pulse_interval_ticks_value
	_is_configured = true


static func _is_non_negative_finite(value: float) -> bool:
	return is_finite(value) and value >= 0.0
