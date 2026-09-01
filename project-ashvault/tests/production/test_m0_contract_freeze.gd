extends SceneTree

const ContentCatalog = preload("res://game/content/content_catalog.gd")
const ContentDefinition = preload("res://game/content/content_definition.gd")
const PerformanceMetrics = preload("res://game/infrastructure/performance_metrics.gd")
const StableId = preload("res://game/content/stable_id.gd")
const TagRegistry = preload("res://game/content/tag_registry.gd")
const VersionInfo = preload("res://game/infrastructure/version_info.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_stable_identity_contract()
	_test_version_contract()
	_test_public_method_surface()
	_test_content_definition_properties()
	_test_performance_report_schema_version()

	if failures.is_empty():
		print("M0 contract freeze tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_stable_identity_contract() -> void:
	_assert_equal(
		StableId.PATTERN,
		"^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$",
		"Stable ID syntax is a frozen content compatibility contract."
	)


func _test_version_contract() -> void:
	_assert_equal(VersionInfo.CONTENT_VERSION, 1, "Content version must remain explicit.")
	_assert_equal(
		VersionInfo.SIMULATION_VERSION,
		1,
		"Simulation version must remain explicit."
	)
	_assert_equal(
		VersionInfo.SAVE_SCHEMA_VERSION,
		1,
		"Save schema version must remain explicit."
	)
	_assert_equal(
		VersionInfo.snapshot(),
		{
			"content_version": 1,
			"simulation_version": 1,
			"save_schema_version": 1,
		},
		"Version snapshots must retain stable field names."
	)


func _test_public_method_surface() -> void:
	_assert_script_methods(StableId, ["is_valid", "validation_error"])
	_assert_script_methods(
		TagRegistry,
		[
			"register_tag",
			"register_tags",
			"contains",
			"validate_known",
			"all_tags",
			"freeze",
			"is_frozen",
		]
	)
	_assert_script_methods(ContentDefinition, ["configure", "freeze", "is_frozen"])
	_assert_script_methods(
		ContentCatalog,
		["load_definitions", "is_loaded", "get_definition", "ids"]
	)
	_assert_script_methods(
		PerformanceMetrics,
		["record_tick", "sample_count", "build_report"]
	)


func _test_content_definition_properties() -> void:
	var definition := ContentDefinition.new()
	var property_names: Array[String] = []
	for property: Dictionary in definition.get_property_list():
		property_names.append(property.get("name", ""))
	for required_property in ["content_id", "tags", "dependencies"]:
		_assert_true(
			property_names.has(required_property),
			"GameContentDefinition must expose '%s'." % required_property
		)


func _test_performance_report_schema_version() -> void:
	_assert_equal(
		PerformanceMetrics.REPORT_SCHEMA_VERSION,
		1,
		"Performance report schema version must remain explicit."
	)


func _assert_script_methods(script: Script, required_methods: Array[String]) -> void:
	var method_names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		method_names.append(method.get("name", ""))
	for required_method in required_methods:
		_assert_true(
			method_names.has(required_method),
			"%s must retain public method '%s'." % [script.resource_path, required_method]
		)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
