class_name StableId
extends RefCounted

const SYNTAX := "lowercase dotted segments; each segment starts with a letter and may contain digits or underscores"
const PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"


static func is_valid(value: String) -> bool:
	return validation_error(value).is_empty()


static func validation_error(value: String) -> String:
	if value.is_empty():
		return "Stable ID must not be empty; expected %s." % SYNTAX

	var expression := RegEx.new()
	var compile_error := expression.compile(PATTERN)
	assert(compile_error == OK, "Stable ID validation pattern must compile.")
	if expression.search(value) == null:
		return "Invalid stable ID '%s'; expected %s." % [value, SYNTAX]
	return ""
