extends SceneTree

const StableId = preload("res://game/content/stable_id.gd")
const TagRegistry = preload("res://game/content/tag_registry.gd")
const VersionInfo = preload("res://game/infrastructure/version_info.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stable_id_syntax()
	_test_tag_registry()
	_test_version_contract()

	if failures.is_empty():
		print("Production identity contract tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_stable_id_syntax() -> void:
	var valid_ids: Array[String] = [
		"ability.stormweaver.arc_bolt",
		"damage.lightning",
		"item.green_storm_eye",
	]
	for value in valid_ids:
		_assert_true(StableId.is_valid(value), "Expected valid stable ID: %s" % value)
		_assert_equal(StableId.validation_error(value), "", "Valid IDs must not report errors.")

	var invalid_ids: Array[String] = [
		"",
		"ability",
		"Ability.arc_bolt",
		"ability..arc_bolt",
		"ability.arc-bolt",
		"ability.2bolt",
		" ability.arc_bolt",
	]
	for value in invalid_ids:
		_assert_true(not StableId.is_valid(value), "Expected invalid stable ID: %s" % value)
		_assert_true(
			not StableId.validation_error(value).is_empty(),
			"Invalid IDs must return an actionable error: %s" % value
		)


func _test_tag_registry() -> void:
	var registry := TagRegistry.new()
	_assert_equal(registry.register_tag("damage.lightning"), "", "Valid tag registration must succeed.")
	_assert_true(registry.contains("damage.lightning"), "Registered tags must be discoverable.")
	_assert_true(
		registry.register_tag("damage.lightning").contains("already registered"),
		"Duplicate tags must return a diagnostic."
	)
	_assert_true(
		registry.register_tag("Damage.Fire").contains("Invalid tag"),
		"Invalid tags must return a diagnostic."
	)
	_assert_equal(
		registry.register_tags(["delivery.projectile", "event.hit"]),
		PackedStringArray(),
		"A valid tag batch must register atomically."
	)
	_assert_equal(
		registry.all_tags(),
		PackedStringArray(["damage.lightning", "delivery.projectile", "event.hit"]),
		"Published tags must be sorted and stable."
	)

	var batch_errors := registry.register_tags(["damage.cold", "Damage.Invalid"])
	_assert_true(batch_errors.size() == 1, "An invalid batch must report its errors.")
	_assert_true(
		not registry.contains("damage.cold"),
		"An invalid tag batch must not partially mutate the registry."
	)
	var duplicate_errors := registry.register_tags(["damage.fire", "damage.fire"])
	_assert_true(duplicate_errors.size() == 1, "Batch-local duplicates must be diagnosed.")
	_assert_true(
		not registry.contains("damage.fire"),
		"A duplicate tag batch must not partially mutate the registry."
	)

	var unknown_errors := registry.validate_known(["damage.lightning", "damage.cold"])
	_assert_true(unknown_errors.size() == 1, "Exactly one unknown tag must be reported.")
	_assert_true(unknown_errors[0].contains("damage.cold"), "Unknown tag diagnostics must name the tag.")

	registry.freeze()
	_assert_true(registry.is_frozen(), "The tag registry must expose frozen state.")
	_assert_true(
		registry.register_tag("damage.cold").contains("frozen"),
		"Frozen registries must reject mutation."
	)


func _test_version_contract() -> void:
	var versions := VersionInfo.snapshot()
	_assert_true(versions.size() == 3, "Exactly three independent version axes are required.")
	_assert_true(versions.has("content_version"), "Content version must be explicit.")
	_assert_true(versions.has("simulation_version"), "Simulation version must be explicit.")
	_assert_true(versions.has("save_schema_version"), "Save schema version must be explicit.")
	for key: String in versions:
		_assert_true(int(versions[key]) >= 1, "%s must be positive." % key)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s Expected %s, got %s." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
