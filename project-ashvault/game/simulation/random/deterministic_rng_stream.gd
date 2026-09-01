class_name DeterministicRngStream
extends RefCounted

var _stream_name := &""
var _initial_seed := 0
var _generator := RandomNumberGenerator.new()


func next_u32() -> int:
	return _generator.randi()


func next_int(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "Minimum RNG bound must not exceed maximum.")
	return _generator.randi_range(minimum, maximum)


func next_float() -> float:
	return _generator.randf()


func next_float_range(minimum: float, maximum: float) -> float:
	assert(minimum <= maximum, "Minimum RNG bound must not exceed maximum.")
	return _generator.randf_range(minimum, maximum)


func snapshot() -> Dictionary:
	return {
		"name": String(_stream_name),
		"seed": str(_initial_seed),
		"state": str(_generator.state),
	}


func _configure(stream_name: StringName, initial_seed: int) -> void:
	_stream_name = stream_name
	_initial_seed = initial_seed
	_generator.seed = initial_seed


func _restore(initial_seed: int, restored_state: int) -> void:
	_initial_seed = initial_seed
	_generator.seed = initial_seed
	_generator.state = restored_state
