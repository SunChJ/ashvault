extends SceneTree

const RngStreams = preload("res://game/simulation/random/rng_streams.gd")

const ROOT_SEED := 42
const SAMPLE_SIZE := 8

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_golden_sequence()
	_test_identical_root_seed_replays_sequences()
	_test_stream_call_counts_are_isolated()
	_test_snapshot_round_trips_through_json()
	_test_invalid_restore_is_transactional()
	_test_snapshot_validation()
	_test_sampling_ranges()
	_test_unknown_stream_is_rejected()

	if failures.is_empty():
		print("Production RNG stream tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_golden_sequence() -> void:
	var streams := RngStreams.new()
	streams.initialize(ROOT_SEED)
	var expected: Dictionary = {
		RngStreams.COMBAT: [
			1406251421,
			912111667,
			536956551,
			3058275898,
			1691895155,
			1412070449,
			997265694,
			444369661,
		],
		RngStreams.LOOT: [
			1820965340,
			2992805526,
			1984388450,
			337725301,
			2387722158,
			410458839,
			2924467103,
			1730144797,
		],
		RngStreams.DUNGEON: [
			166006577,
			3821573425,
			914037069,
			2208076787,
			3042662428,
			2857636162,
			1630403642,
			2803600714,
		],
	}
	for stream_name in RngStreams.STREAM_NAMES:
		_assert_equal(
			_sample(streams.get_stream(stream_name)),
			expected[stream_name],
			"The pinned simulation version must retain the '%s' golden sequence."
			% stream_name
		)


func _test_identical_root_seed_replays_sequences() -> void:
	var first := RngStreams.new()
	var second := RngStreams.new()
	first.initialize(ROOT_SEED)
	second.initialize(ROOT_SEED)

	for stream_name in RngStreams.STREAM_NAMES:
		_assert_equal(
			_sample(first.get_stream(stream_name)),
			_sample(second.get_stream(stream_name)),
			"Stream '%s' must replay from an identical root seed." % stream_name
		)

	var snapshot := first.snapshot()
	var derived_seeds: Dictionary = {}
	for stream_name in RngStreams.STREAM_NAMES:
		derived_seeds[snapshot["streams"][stream_name]["seed"]] = true
	_assert_equal(
		derived_seeds.size(),
		RngStreams.STREAM_NAMES.size(),
		"Named streams must receive distinct derived seeds."
	)


func _test_stream_call_counts_are_isolated() -> void:
	var advanced := RngStreams.new()
	var control := RngStreams.new()
	advanced.initialize(ROOT_SEED)
	control.initialize(ROOT_SEED)

	_sample(advanced.get_stream(RngStreams.LOOT), 100)
	_assert_equal(
		_sample(advanced.get_stream(RngStreams.COMBAT)),
		_sample(control.get_stream(RngStreams.COMBAT)),
		"Loot calls must not advance the combat stream."
	)
	_assert_equal(
		_sample(advanced.get_stream(RngStreams.DUNGEON)),
		_sample(control.get_stream(RngStreams.DUNGEON)),
		"Loot calls must not advance the dungeon stream."
	)


func _test_snapshot_round_trips_through_json() -> void:
	var original := RngStreams.new()
	original.initialize(-9223372036854775808)
	for stream_name in RngStreams.STREAM_NAMES:
		_sample(original.get_stream(stream_name), 7)

	var serialized := JSON.stringify(original.snapshot())
	var parsed: Variant = JSON.parse_string(serialized)
	var restored := RngStreams.new()
	restored.initialize(999)
	var retained_combat_handle := restored.get_stream(RngStreams.COMBAT)
	var errors := restored.restore(parsed)

	_assert_equal(errors, PackedStringArray(), "A valid JSON snapshot must restore.")
	_assert_true(
		retained_combat_handle == restored.get_stream(RngStreams.COMBAT),
		"Successful restore must preserve acquired stream handles."
	)
	_assert_equal(restored.snapshot(), original.snapshot(), "Restored state must be exact.")
	for stream_name in RngStreams.STREAM_NAMES:
		_assert_equal(
			_sample(restored.get_stream(stream_name)),
			_sample(original.get_stream(stream_name)),
			"Restored stream '%s' must continue the same sequence." % stream_name
		)


func _test_invalid_restore_is_transactional() -> void:
	var streams := RngStreams.new()
	streams.initialize(ROOT_SEED)
	_sample(streams.get_stream(RngStreams.COMBAT), 3)
	var before := streams.snapshot()
	var control := RngStreams.new()
	_assert_equal(control.restore(before), PackedStringArray(), "Control restore must succeed.")

	var invalid: Dictionary = before.duplicate(true)
	invalid["streams"].erase(RngStreams.DUNGEON)
	var errors := streams.restore(invalid)
	_assert_contains(errors, "Missing stream 'dungeon'", "Missing streams must be diagnosed.")
	_assert_equal(
		_sample(streams.get_stream(RngStreams.COMBAT)),
		_sample(control.get_stream(RngStreams.COMBAT)),
		"Rejected restore must not mutate existing stream state."
	)

	invalid = before.duplicate(true)
	invalid["streams"][RngStreams.LOOT]["name"] = RngStreams.COMBAT
	errors = streams.restore(invalid)
	_assert_contains(errors, "name must match", "Mismatched stream names must be diagnosed.")

	invalid = before.duplicate(true)
	invalid["streams"][RngStreams.LOOT]["state"] = "01"
	errors = streams.restore(invalid)
	_assert_contains(errors, "canonical signed decimal", "Unsafe state strings must be rejected.")


func _test_snapshot_validation() -> void:
	var source := RngStreams.new()
	source.initialize(ROOT_SEED)
	var valid := source.snapshot()
	var target := RngStreams.new()

	var invalid: Dictionary = valid.duplicate(true)
	invalid["schema_version"] = 2
	_assert_contains(
		target.restore(invalid),
		"schema_version",
		"Unknown snapshot versions must be rejected."
	)

	invalid = valid.duplicate(true)
	invalid["streams"]["encounter"] = invalid["streams"][RngStreams.DUNGEON]
	_assert_contains(
		target.restore(invalid),
		"Unexpected RNG stream",
		"Extra streams must be rejected."
	)

	invalid = valid.duplicate(true)
	invalid["streams"][RngStreams.COMBAT]["extra"] = true
	_assert_contains(
		target.restore(invalid),
		"unexpected field",
		"Extra stream fields must be rejected."
	)

	invalid = valid.duplicate(true)
	invalid["streams"][RngStreams.COMBAT]["seed"] = "1"
	_assert_contains(
		target.restore(invalid),
		"does not match root_seed",
		"Derived seeds must match the root seed and stream domain."
	)


func _test_sampling_ranges() -> void:
	var streams := RngStreams.new()
	streams.initialize(ROOT_SEED)
	var combat := streams.get_stream(RngStreams.COMBAT)
	for index in 100:
		var integer: int = combat.next_int(-3, 5)
		_assert_true(integer >= -3 and integer <= 5, "Integer samples must honor bounds.")
		var unit_float: float = combat.next_float()
		_assert_true(
			unit_float >= 0.0 and unit_float <= 1.0,
			"Unit float samples must honor bounds."
		)
		var ranged_float: float = combat.next_float_range(-2.5, 7.5)
		_assert_true(
			ranged_float >= -2.5 and ranged_float <= 7.5,
			"Ranged float samples must honor bounds."
		)


func _test_unknown_stream_is_rejected() -> void:
	var streams := RngStreams.new()
	streams.initialize(ROOT_SEED)
	_assert_true(
		streams.get_stream(&"encounter") == null,
		"Unknown stream names must not create implicit generators."
	)


func _sample(stream: RefCounted, count: int = SAMPLE_SIZE) -> Array[int]:
	var values: Array[int] = []
	for index in count:
		values.append(stream.next_u32())
	return values


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
