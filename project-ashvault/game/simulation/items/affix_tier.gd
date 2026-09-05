class_name AffixTier
extends Resource

var _frozen := false
var _number: int = 1
var _minimum_level: int = 1
var _minimum: float = 0.0
var _maximum: float = 0.0

@export var number: int:
	get:
		return _number
	set(value):
		if not is_frozen():
			_number = value

@export var minimum_level: int:
	get:
		return _minimum_level
	set(value):
		if not is_frozen():
			_minimum_level = value

@export var minimum: float:
	get:
		return _minimum
	set(value):
		if not is_frozen():
			_minimum = value

@export var maximum: float:
	get:
		return _maximum
	set(value):
		if not is_frozen():
			_maximum = value


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true


func validation_error() -> String:
	if number < 1 or number > 5 or minimum_level < 1 or minimum_level > 2147483647:
		return "Affix tiers require T1–T5 and a positive 32-bit level."
	if not is_finite(minimum) or not is_finite(maximum) or minimum > maximum or absf(minimum) > 1000000.0 or absf(maximum) > 1000000.0:
		return "Affix tier bounds must be finite, ordered, and within ±1000000."
	return ""
