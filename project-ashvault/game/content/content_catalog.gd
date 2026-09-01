class_name ContentCatalog
extends RefCounted

const ContentDefinitionContract = preload("res://game/content/content_definition.gd")
const StableIdContract = preload("res://game/content/stable_id.gd")
const TagRegistryContract = preload("res://game/content/tag_registry.gd")

enum VisitState {
	UNVISITED,
	VISITING,
	VISITED,
}

var _definitions: Dictionary = {}
var _is_loaded := false


func load_definitions(definitions: Array, tag_registry: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if _is_loaded:
		errors.append("Content catalog is already loaded and immutable.")
		return errors
	if not tag_registry is TagRegistryContract:
		errors.append("Content catalog requires a TagRegistry.")
		return errors
	if tag_registry.is_frozen():
		errors.append("Tag registry must remain mutable until catalog publication.")
		return errors

	var staged: Dictionary = {}
	for index in definitions.size():
		var definition: Variant = definitions[index]
		if not definition is ContentDefinitionContract:
			errors.append("Definition at index %d is not a GameContentDefinition." % index)
			continue
		if definition.is_frozen():
			errors.append("Definition '%s' is already frozen." % definition.content_id)
			continue

		var id_error := StableIdContract.validation_error(definition.content_id)
		if not id_error.is_empty():
			errors.append(id_error)
			continue
		var key := StringName(definition.content_id)
		if staged.has(key):
			errors.append("Duplicate content ID '%s'." % definition.content_id)
			continue
		staged[key] = definition

	if not errors.is_empty():
		return errors

	_validate_tags(staged, tag_registry, errors)
	_validate_dependencies(staged, errors)
	if errors.is_empty():
		var cycle := _find_dependency_cycle(staged)
		if not cycle.is_empty():
			errors.append("Dependency cycle detected: %s." % " -> ".join(cycle))
	if not errors.is_empty():
		return errors

	for definition: Variant in staged.values():
		definition.freeze()
	tag_registry.freeze()
	_definitions = staged
	_is_loaded = true
	return errors


func is_loaded() -> bool:
	return _is_loaded


func get_definition(content_id: String) -> Variant:
	if not _is_loaded:
		return null
	return _definitions.get(StringName(content_id))


func ids() -> PackedStringArray:
	var result := PackedStringArray()
	if not _is_loaded:
		return result
	for content_id: StringName in _definitions:
		result.append(String(content_id))
	result.sort()
	return result


func _validate_tags(
	staged: Dictionary,
	tag_registry: Variant,
	errors: PackedStringArray
) -> void:
	for content_id in _sorted_keys(staged):
		var definition: Variant = staged[StringName(content_id)]
		var observed: Dictionary = {}
		for tag: String in definition.tags:
			var key := StringName(tag)
			if observed.has(key):
				errors.append("Definition '%s' repeats tag '%s'." % [content_id, tag])
				continue
			observed[key] = true
			if not tag_registry.contains(tag):
				errors.append("Definition '%s': Unknown tag '%s'." % [content_id, tag])


func _validate_dependencies(staged: Dictionary, errors: PackedStringArray) -> void:
	for content_id in _sorted_keys(staged):
		var definition: Variant = staged[StringName(content_id)]
		var observed: Dictionary = {}
		for dependency: String in definition.dependencies:
			var dependency_error := StableIdContract.validation_error(dependency)
			if not dependency_error.is_empty():
				errors.append("Definition '%s': %s" % [content_id, dependency_error])
				continue
			var key := StringName(dependency)
			if observed.has(key):
				errors.append(
					"Definition '%s' repeats dependency '%s'." % [content_id, dependency]
				)
				continue
			observed[key] = true
			if not staged.has(key):
				errors.append(
					"Definition '%s': Missing dependency '%s'." % [content_id, dependency]
				)


func _find_dependency_cycle(staged: Dictionary) -> PackedStringArray:
	var states: Dictionary = {}
	var stack: Array[String] = []
	for content_id in _sorted_keys(staged):
		if int(states.get(content_id, VisitState.UNVISITED)) != VisitState.UNVISITED:
			continue
		var cycle := _visit_dependency(content_id, staged, states, stack)
		if not cycle.is_empty():
			return cycle
	return PackedStringArray()


func _visit_dependency(
	content_id: String,
	staged: Dictionary,
	states: Dictionary,
	stack: Array[String]
) -> PackedStringArray:
	states[content_id] = VisitState.VISITING
	stack.append(content_id)
	var definition: Variant = staged[StringName(content_id)]
	var dependencies: Array[String] = definition.dependencies
	dependencies.sort()
	for dependency in dependencies:
		var state := int(states.get(dependency, VisitState.UNVISITED))
		if state == VisitState.VISITING:
			var cycle := PackedStringArray()
			var cycle_start := stack.find(dependency)
			for index in range(cycle_start, stack.size()):
				cycle.append(stack[index])
			cycle.append(dependency)
			return cycle
		if state == VisitState.UNVISITED:
			var nested_cycle := _visit_dependency(dependency, staged, states, stack)
			if not nested_cycle.is_empty():
				return nested_cycle

	stack.pop_back()
	states[content_id] = VisitState.VISITED
	return PackedStringArray()


func _sorted_keys(values: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for key: StringName in values:
		result.append(String(key))
	result.sort()
	return result
