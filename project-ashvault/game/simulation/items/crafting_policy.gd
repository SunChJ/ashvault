class_name CraftingPolicy
extends Resource

var _frozen := false
var _quality_rate: int = 2
var _socket_rate: int = 5
var _reroll_rate: int = 10
var _insertion_cost: int = 1
var _salvage_yields: Dictionary = {"white": 1, "blue": 2, "gold": 4, "green": 4, "purple": 4, "red": 4, "set": 4}

@export var quality_rate: int:
	get:
		return _quality_rate
	set(value):
		if not _frozen:
			_quality_rate = value

@export var socket_rate: int:
	get:
		return _socket_rate
	set(value):
		if not _frozen:
			_socket_rate = value

@export var reroll_rate: int:
	get:
		return _reroll_rate
	set(value):
		if not _frozen:
			_reroll_rate = value

@export var insertion_cost: int:
	get:
		return _insertion_cost
	set(value):
		if not _frozen:
			_insertion_cost = value

@export var salvage_yields: Dictionary:
	get:
		return _salvage_yields.duplicate()
	set(value):
		if not _frozen:
			_salvage_yields = value.duplicate()


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true
