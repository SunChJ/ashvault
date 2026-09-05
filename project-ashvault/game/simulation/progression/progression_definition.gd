class_name ProgressionDefinition
extends Resource

var _frozen := false
var _xp_thresholds: Array[int] = [0, 100]
var _points_per_level: int = 1
var _max_skill_rank: int = 20

@export var xp_thresholds: Array[int]:
	get:
		return _xp_thresholds.duplicate()
	set(value):
		if not _frozen:
			_xp_thresholds = value.duplicate()

@export var points_per_level: int:
	get:
		return _points_per_level
	set(value):
		if not _frozen:
			_points_per_level = value

@export var max_skill_rank: int:
	get:
		return _max_skill_rank
	set(value):
		if not _frozen:
			_max_skill_rank = value


func is_frozen() -> bool:
	return _frozen


func freeze() -> void:
	_frozen = true
