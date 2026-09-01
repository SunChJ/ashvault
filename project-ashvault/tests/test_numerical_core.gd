extends SceneTree

const CombatMath = preload("res://prototype/core/combat_math.gd")
const ProgressionMath = preload("res://prototype/core/progression_math.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_damage_pipeline()
	_test_critical_and_resistance_boundaries()
	_test_haste_diminishing_returns()
	_test_experience_curve()
	_test_skill_milestones()

	if _failures.is_empty():
		print("Numerical core tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_damage_pipeline() -> void:
	var damage := CombatMath.resolve_hit(
		100.0,
		0.5,
		20.0,
		0.8,
		[1.25, 1.2],
		false,
		0.2,
		0.4,
		0.1,
		0.25
	)
	_assert_approx(damage, 401.625, 0.001, "Damage stages must resolve in order.")


func _test_critical_and_resistance_boundaries() -> void:
	var normal := CombatMath.resolve_hit(10.0, 0.0, 0.0, 0.0, [], false)
	var critical := CombatMath.resolve_hit(10.0, 0.0, 0.0, 0.0, [], true, 2.0)
	_assert_approx(normal, 10.0, 0.001, "A neutral hit must preserve base damage.")
	_assert_approx(critical, 20.0, 0.001, "Critical multiplier must apply once.")
	_assert_approx(
		CombatMath.resistance_multiplier(0.85, 0.0),
		0.15,
		0.001,
		"Positive resistance must reduce damage."
	)
	_assert_approx(
		CombatMath.resistance_multiplier(0.2, 0.5),
		1.3,
		0.001,
		"Penetration may push resistance below zero."
	)


func _test_haste_diminishing_returns() -> void:
	var first_half := CombatMath.effective_haste(0.5)
	var full := CombatMath.effective_haste(1.0)
	var second_half_gain := full - first_half
	_assert_true(full > first_half, "More raw haste must always help.")
	_assert_true(
		second_half_gain < first_half,
		"Haste gains must diminish after the first investment."
	)
	_assert_true(
		CombatMath.interval_after_haste(1.0, 1.0) < CombatMath.interval_after_haste(1.0, 0.5),
		"More haste must reduce action interval."
	)


func _test_experience_curve() -> void:
	var previous := 0
	for level in range(1, 31):
		var required := ProgressionMath.xp_to_next(level)
		_assert_true(required > previous, "XP must increase at level %d." % level)
		previous = required

	_assert_true(
		ProgressionMath.xp_to_next(6) - ProgressionMath.xp_to_next(5)
		> ProgressionMath.xp_to_next(5) - ProgressionMath.xp_to_next(4),
		"The first XP breakpoint must increase slope."
	)
	_assert_true(
		ProgressionMath.xp_to_next(11) - ProgressionMath.xp_to_next(10)
		> ProgressionMath.xp_to_next(10) - ProgressionMath.xp_to_next(9),
		"The second XP breakpoint must increase slope."
	)


func _test_skill_milestones() -> void:
	_assert_true(
		ProgressionMath.skill_damage_multiplier(5) > ProgressionMath.skill_damage_multiplier(4),
		"Skill damage must grow by rank."
	)
	_assert_true(
		ProgressionMath.projectile_count(2) == 1,
		"Rank 2 must retain one projectile."
	)
	_assert_true(
		ProgressionMath.projectile_count(3) == 2,
		"Rank 3 must add a projectile."
	)
	_assert_true(
		ProgressionMath.chain_count(5) == 1,
		"Rank 5 must unlock chaining."
	)


func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s Expected %.4f, got %.4f." % [message, expected, actual])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
