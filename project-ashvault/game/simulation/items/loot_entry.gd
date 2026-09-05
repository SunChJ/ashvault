class_name LootEntry
extends Resource

var _frozen := false
var _entry_id: String = ""
var _definition_id: String = ""
var _rarity: String = ""
var _weight: int = 1

@export var entry_id: String:
	get:
		return _entry_id
	set(value):
		if not _frozen:
			_entry_id = value

@export var definition_id: String:
	get:
		return _definition_id
	set(value):
		if not _frozen:
			_definition_id = value

@export var rarity: String:
	get:
		return _rarity
	set(value):
		if not _frozen:
			_rarity = value

@export var weight: int:
	get:
		return _weight
	set(value):
		if not _frozen:
			_weight = value


func freeze() -> void:
	_frozen = true
