class_name RngStreams
extends RefCounted

const DeterministicStream = preload(
	"res://game/simulation/random/deterministic_rng_stream.gd"
)

const SNAPSHOT_SCHEMA_VERSION := 1
const DERIVATION_DOMAIN := "ashvault.rng.v1"
const COMBAT := &"combat"
const LOOT := &"loot"
const DUNGEON := &"dungeon"
const STREAM_NAMES: Array[StringName] = [COMBAT, LOOT, DUNGEON]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"root_seed",
	"streams",
]
const STREAM_FIELDS: Array[String] = ["name", "seed", "state"]

var _root_seed := 0
var _streams: Dictionary = {}
var _is_initialized := false


func initialize(root_seed: int) -> void:
	_root_seed = root_seed
	_streams.clear()
	for stream_name in STREAM_NAMES:
		var stream := DeterministicStream.new()
		stream._configure(stream_name, _derive_seed(root_seed, stream_name))
		_streams[stream_name] = stream
	_is_initialized = true


func is_initialized() -> bool:
	return _is_initialized


func get_stream(stream_name: StringName) -> RefCounted:
	if not _is_initialized or not STREAM_NAMES.has(stream_name):
		return null
	return _streams.get(stream_name)


func snapshot() -> Dictionary:
	if not _is_initialized:
		return {}

	var stream_snapshots: Dictionary = {}
	for stream_name in STREAM_NAMES:
		stream_snapshots[String(stream_name)] = _streams[stream_name].snapshot()
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"root_seed": str(_root_seed),
		"streams": stream_snapshots,
	}


func restore(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("RNG snapshot must be an object.")
		return errors
	var snapshot_value: Dictionary = value
	_validate_exact_fields(snapshot_value, SNAPSHOT_FIELDS, "RNG snapshot", errors)
	var schema_version: Variant = snapshot_value.get("schema_version")
	var schema_type := typeof(schema_version)
	if (
		schema_type != TYPE_INT and schema_type != TYPE_FLOAT
	) or schema_version != SNAPSHOT_SCHEMA_VERSION:
		errors.append(
			"RNG snapshot schema_version must equal %d." % SNAPSHOT_SCHEMA_VERSION
		)

	var root_seed_value: Variant = _parse_decimal(
		snapshot_value.get("root_seed"),
		"RNG snapshot root_seed",
		errors
	)
	var streams_value: Variant = snapshot_value.get("streams")
	if not streams_value is Dictionary:
		errors.append("RNG snapshot streams must be an object.")
		return errors

	var snapshot_streams: Dictionary = streams_value
	for key: Variant in snapshot_streams:
		if not STREAM_NAMES.has(StringName(str(key))):
			errors.append("Unexpected RNG stream '%s'." % key)
	for stream_name in STREAM_NAMES:
		if not snapshot_streams.has(String(stream_name)):
			errors.append("Missing stream '%s'." % stream_name)

	var restored_values: Dictionary = {}
	if root_seed_value != null:
		for stream_name in STREAM_NAMES:
			var key := String(stream_name)
			if not snapshot_streams.has(key):
				continue
			var stream_value: Variant = snapshot_streams[key]
			if not stream_value is Dictionary:
				errors.append("RNG stream '%s' must be an object." % stream_name)
				continue
			var stream_snapshot: Dictionary = stream_value
			_validate_exact_fields(
				stream_snapshot,
				STREAM_FIELDS,
				"RNG stream '%s'" % stream_name,
				errors
			)
			if stream_snapshot.get("name") != key:
				errors.append("RNG stream '%s' name must match its key." % stream_name)
			var seed_value: Variant = _parse_decimal(
				stream_snapshot.get("seed"),
				"RNG stream '%s' seed" % stream_name,
				errors
			)
			var state_value: Variant = _parse_decimal(
				stream_snapshot.get("state"),
				"RNG stream '%s' state" % stream_name,
				errors
			)
			if seed_value != null and seed_value != _derive_seed(
				int(root_seed_value),
				stream_name
			):
				errors.append(
					"RNG stream '%s' seed does not match root_seed." % stream_name
				)
			if seed_value != null and state_value != null:
				restored_values[stream_name] = {
					"seed": seed_value,
					"state": state_value,
				}

	if not errors.is_empty():
		return errors

	if not _is_initialized:
		initialize(int(root_seed_value))
	_root_seed = int(root_seed_value)
	for stream_name in STREAM_NAMES:
		var restored: Dictionary = restored_values[stream_name]
		_streams[stream_name]._restore(
			int(restored["seed"]),
			int(restored["state"])
		)
	return errors


func _derive_seed(root_seed: int, stream_name: StringName) -> int:
	var input := "%s|%s|%s" % [DERIVATION_DOMAIN, root_seed, stream_name]
	var context := HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(input.to_utf8_buffer()) == OK)
	var digest := context.finish()
	var derived_seed := 0
	for index in 7:
		derived_seed = (derived_seed << 8) | int(digest[index])
	return derived_seed


func _parse_decimal(value: Variant, path: String, errors: PackedStringArray) -> Variant:
	if not value is String:
		errors.append("%s must be a canonical signed decimal string." % path)
		return null
	var decimal: String = value
	var parsed := decimal.to_int()
	if str(parsed) != decimal:
		errors.append("%s must be a canonical signed decimal string." % path)
		return null
	return parsed


func _validate_exact_fields(
	value: Dictionary,
	expected_fields: Array[String],
	path: String,
	errors: PackedStringArray
) -> void:
	for expected_field in expected_fields:
		if not value.has(expected_field):
			errors.append("%s is missing field '%s'." % [path, expected_field])
	for field: Variant in value:
		if not expected_fields.has(str(field)):
			errors.append("%s has unexpected field '%s'." % [path, field])
