# Deterministic Random Streams

`RngStreams` owns the run-level `combat`, `loot`, and `dungeon` generators.
`DeterministicRngStream` is the only production wrapper allowed to instantiate
Godot's `RandomNumberGenerator`.

Consumers acquire a stream with `get_stream()` and use `next_u32()`,
`next_int()`, `next_float()`, or `next_float_range()`. They do not retain or
modify raw generator state. Run persistence stores the manager's versioned
snapshot and restores it before simulation resumes.
