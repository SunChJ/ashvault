extends SceneTree

const SketchScene = preload("res://prototype/numerical_sketch.tscn")

var failures: Array[String] = []


func _init() -> void:
	var sketch := SketchScene.instantiate()
	root.add_child(sketch)
	sketch.set_physics_process(false)
	sketch.rng.seed = 0xA55A_17
	sketch.arena_size = Vector2(1152.0, 648.0)
	sketch.player_position = sketch.arena_size * 0.5
	sketch.player_max_health = 1_000_000.0
	sketch.player_health = sketch.player_max_health

	for frame in 60 * 180:
		var sample_time := float(frame) / 60.0
		sketch.player_position = sketch.arena_size * 0.5 + Vector2(
			cos(sample_time * 0.72) * 210.0,
			sin(sample_time * 0.93) * 135.0
		)
		if sketch.choosing_upgrade:
			sketch._apply_upgrade(sketch.upgrade_options[0])
		sketch._physics_process(1.0 / 60.0)

	var snapshot: Dictionary = sketch.debug_snapshot()
	_assert_between(float(snapshot["first_upgrade_time"]), 8.0, 18.0, "First upgrade cadence")
	_assert_between(float(snapshot["first_overdrive_time"]), 10.0, 90.0, "First Overdrive cadence")
	_assert_between(float(snapshot["first_boss_time"]), 119.0, 121.0, "First boss cadence")
	_assert_true(int(snapshot["level"]) >= 8, "The run must create a build within three minutes.")
	_assert_true(int(snapshot["storm_rank"]) >= 3, "The first behavior milestone must be reachable.")
	_assert_true(int(snapshot["kills"]) >= 100, "The run must sustain a high kill cadence.")
	_assert_true(int(snapshot["peak_enemies"]) >= 30, "Enemy density must reach the intended power-fantasy band.")
	_assert_true(int(snapshot["peak_enemies"]) <= 120, "Enemy density must remain readable in the sample.")
	_assert_true(not bool(snapshot["game_over"]), "The seeded balance sample must complete.")

	print("Numerical sketch sample: %s" % JSON.stringify(snapshot))
	if failures.is_empty():
		print("Numerical sketch tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_between(value: float, minimum: float, maximum: float, label: String) -> void:
	if value < minimum or value > maximum:
		failures.append("%s expected %.2f...%.2f, got %.2f." % [label, minimum, maximum, value])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
