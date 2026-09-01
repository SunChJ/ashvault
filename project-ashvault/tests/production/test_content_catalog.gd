extends SceneTree

const ContentDefinition = preload("res://game/content/content_definition.gd")
const ContentCatalog = preload("res://game/content/content_catalog.gd")
const TagRegistry = preload("res://game/content/tag_registry.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_valid_catalog_is_published_and_frozen()
	_test_duplicate_ids_are_rejected()
	_test_unknown_tags_are_rejected()
	_test_missing_dependencies_are_rejected()
	_test_dependency_cycles_are_rejected()

	if failures.is_empty():
		print("Production content catalog tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_valid_catalog_is_published_and_frozen() -> void:
	var tags := _tag_registry(["content.test", "damage.lightning"])
	var dependency := _definition("content.dependency", ["content.test"])
	var root := _definition(
		"content.root",
		["content.test", "damage.lightning"],
		["content.dependency"]
	)
	var catalog := ContentCatalog.new()
	var errors := catalog.load_definitions([root, dependency], tags)

	_assert_equal(errors, PackedStringArray(), "A valid catalog must load.")
	_assert_true(catalog.is_loaded(), "A valid catalog must publish loaded state.")
	_assert_equal(catalog.ids(), PackedStringArray(["content.dependency", "content.root"]), "Catalog IDs must be stable and sorted.")
	_assert_true(catalog.get_definition("content.root") == root, "Catalog lookup must return the loaded definition.")
	_assert_true(root.is_frozen() and dependency.is_frozen(), "Published definitions must be frozen.")
	_assert_true(tags.is_frozen(), "The tag registry must freeze with the catalog.")
	var empty_values: Array[String] = []
	_assert_true(
		root.configure("content.changed", empty_values, empty_values).contains("frozen"),
		"Frozen definitions must reject reconfiguration."
	)
	root.content_id = "content.changed"
	var leaked_tags: Array[String] = root.tags
	leaked_tags.append("damage.cold")
	_assert_equal(root.content_id, "content.root", "Frozen scalar properties must not mutate.")
	_assert_equal(
		root.tags,
		["content.test", "damage.lightning"],
		"Definition arrays must not expose mutable backing storage."
	)


func _test_duplicate_ids_are_rejected() -> void:
	var tags := _tag_registry(["content.test"])
	var first := _definition("content.duplicate", ["content.test"])
	var second := _definition("content.duplicate", ["content.test"])
	var catalog := ContentCatalog.new()
	var errors := catalog.load_definitions([first, second], tags)

	_assert_contains(errors, "Duplicate content ID 'content.duplicate'", "Duplicate IDs must be diagnosed.")
	_assert_rejected_catalog_remains_mutable(catalog, tags, first)


func _test_unknown_tags_are_rejected() -> void:
	var tags := _tag_registry(["content.test"])
	var definition := _definition("content.unknown_tag", ["damage.void"])
	var catalog := ContentCatalog.new()
	var errors := catalog.load_definitions([definition], tags)

	_assert_contains(errors, "Unknown tag 'damage.void'", "Unknown tags must be diagnosed.")
	_assert_rejected_catalog_remains_mutable(catalog, tags, definition)


func _test_missing_dependencies_are_rejected() -> void:
	var tags := _tag_registry(["content.test"])
	var definition := _definition(
		"content.missing_dependency",
		["content.test"],
		["content.not_present"]
	)
	var catalog := ContentCatalog.new()
	var errors := catalog.load_definitions([definition], tags)

	_assert_contains(errors, "Missing dependency 'content.not_present'", "Missing dependencies must be diagnosed.")
	_assert_rejected_catalog_remains_mutable(catalog, tags, definition)


func _test_dependency_cycles_are_rejected() -> void:
	var tags := _tag_registry(["content.test"])
	var first := _definition("content.first", ["content.test"], ["content.second"])
	var second := _definition("content.second", ["content.test"], ["content.third"])
	var third := _definition("content.third", ["content.test"], ["content.first"])
	var catalog := ContentCatalog.new()
	var errors := catalog.load_definitions([first, second, third], tags)

	_assert_contains(errors, "Dependency cycle detected", "Dependency cycles must be diagnosed.")
	_assert_contains(errors, "content.first", "Cycle diagnostics must include the path.")
	_assert_rejected_catalog_remains_mutable(catalog, tags, first)


func _definition(
	content_id: String,
	tags: Array[String],
	dependencies: Array[String] = []
) -> Resource:
	var definition := ContentDefinition.new()
	var error := definition.configure(content_id, tags, dependencies)
	_assert_equal(error, "", "Synthetic definition setup must succeed.")
	return definition


func _tag_registry(tags: Array[String]) -> RefCounted:
	var registry := TagRegistry.new()
	var errors := registry.register_tags(tags)
	_assert_equal(errors, PackedStringArray(), "Synthetic tag setup must succeed.")
	return registry


func _assert_rejected_catalog_remains_mutable(
	catalog: RefCounted,
	tags: RefCounted,
	definition: Resource
) -> void:
	_assert_true(not catalog.is_loaded(), "Rejected catalogs must not publish partial state.")
	_assert_true(not tags.is_frozen(), "Rejected catalogs must not freeze the tag registry.")
	_assert_true(not definition.is_frozen(), "Rejected catalogs must not freeze definitions.")


func _assert_contains(values: PackedStringArray, needle: String, message: String) -> void:
	for value in values:
		if value.contains(needle):
			return
	failures.append("%s Missing '%s' in %s." % [message, needle, values])


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
