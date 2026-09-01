class_name ProgressionMath
extends RefCounted


static func xp_to_next(level: int) -> int:
	var safe_level := maxi(1, level)
	if safe_level <= 5:
		return 80 + 28 * safe_level + 7 * safe_level * safe_level

	if safe_level <= 10:
		var middle_rank := safe_level - 5
		return 395 + 115 * middle_rank + 18 * middle_rank * middle_rank

	var late_rank := safe_level - 10
	return 1420 + 320 * late_rank + 35 * late_rank * late_rank


static func skill_damage_multiplier(rank: int) -> float:
	var growth_rank := maxi(0, rank - 1)
	return 1.0 + 0.14 * growth_rank + 0.025 * growth_rank * growth_rank


static func projectile_count(rank: int) -> int:
	return 1 + maxi(0, rank) / 3


static func chain_count(rank: int) -> int:
	if rank < 5:
		return 0
	return 1 + (rank - 5) / 4


static func nova_radius(rank: int) -> float:
	return 112.0 + 14.0 * maxi(0, rank - 1)


static func nova_interval(rank: int) -> float:
	return maxf(1.7, 4.1 - 0.18 * maxi(0, rank - 1))
