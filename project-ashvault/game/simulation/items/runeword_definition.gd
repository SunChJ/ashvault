class_name RunewordDefinition
extends Resource

var _frozen := false
var _content_id: String = ""
var _runes: Array[String] = []
var _allowed_bases: Array[String] = []
var _effects: Array[Resource] = []

@export var content_id: String:
	get:
		return _content_id
	set(value):
		if not _frozen:
			_content_id = value

@export var runes: Array[String]:
	get:
		return _runes.duplicate()
	set(value):
		if not _frozen:
			_runes = value.duplicate()

@export var allowed_bases: Array[String]:
	get:
		return _allowed_bases.duplicate()
	set(value):
		if not _frozen:
			_allowed_bases = value.duplicate()

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
