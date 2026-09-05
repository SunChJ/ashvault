class_name PassiveDefinition
extends Resource

var _frozen := false
var _content_id: String = ""
var _minimum_level: int = 1
var _max_rank: int = 1
var _prerequisites: Dictionary = {}
var _modifiers: Array[Resource] = []

@export var content_id: String:
	get:
		return _content_id
	set(value):
		if not _frozen:
			_content_id = value

@export var minimum_level: int:
	get:
		return _minimum_level
	set(value):
		if not _frozen:
			_minimum_level = value

@export var max_rank: int:
	get:
		return _max_rank
	set(value):
		if not _frozen:
			_max_rank = value

@export var prerequisites: Dictionary:
	get:
		return _prerequisites.duplicate()
	set(value):
		if not _frozen:
			_prerequisites = value.duplicate()

@export var modifiers: Array[Resource]:
	get:
		return _modifiers.duplicate()
	set(value):
		if not _frozen:
			_modifiers = value.duplicate()


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	for modifier: Resource in _modifiers:
		modifier.freeze()
	_frozen = true
