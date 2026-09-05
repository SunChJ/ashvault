class_name RuneDefinition
extends Resource

var _frozen := false
var _content_id: String = ""
var _effects: Array[Resource] = []

@export var content_id: String:
	get:
		return _content_id
	set(value):
		if not _frozen:
			_content_id = value

@export var effects: Array[Resource]:
	get:
		return _effects.duplicate()
	set(value):
		if not _frozen:
			_effects = value.duplicate()


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	for effect: Resource in _effects:
		effect.freeze()
	_frozen = true
