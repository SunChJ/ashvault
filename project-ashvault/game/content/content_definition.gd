class_name GameContentDefinition
extends Resource

var _content_id := ""
var _tags: Array[String] = []
var _dependencies: Array[String] = []
var _is_frozen := false

@export var content_id: String:
	get:
		return _content_id
	set(value):
		if not _is_frozen:
			_content_id = value

@export var tags: Array[String]:
	get:
		return _tags.duplicate()
	set(value):
		if not _is_frozen:
			_tags = value.duplicate()

@export var dependencies: Array[String]:
	get:
		return _dependencies.duplicate()
	set(value):
		if not _is_frozen:
			_dependencies = value.duplicate()


func configure(
	new_content_id: String,
	new_tags: Array[String],
	new_dependencies: Array[String]
) -> String:
	if _is_frozen:
		return "Content definition '%s' is frozen." % _content_id
	_content_id = new_content_id
	_tags = new_tags.duplicate()
	_dependencies = new_dependencies.duplicate()
	return ""


func freeze() -> void:
	_is_frozen = true


func is_frozen() -> bool:
	return _is_frozen
