class_name CombatMath
extends RefCounted

const MAX_CRITICAL_CHANCE := 0.95
const MIN_RESISTANCE := -1.0
const MAX_RESISTANCE := 0.85


static func resolve_hit(
	base_damage: float,
	enhanced_damage: float = 0.0,
	flat_damage: float = 0.0,
	increased_damage: float = 0.0,
	more_modifiers: Array = [],
	is_critical: bool = false,
	critical_multiplier: float = 1.5,
	resistance: float = 0.0,
	penetration: float = 0.0,
	conditional_extra: float = 0.0
) -> float:
	var scaled_base := maxf(0.0, base_damage) * maxf(0.0, 1.0 + enhanced_damage)
	var subtotal := maxf(0.0, scaled_base + flat_damage)
	subtotal *= maxf(0.0, 1.0 + increased_damage)

	for modifier: Variant in more_modifiers:
		subtotal *= maxf(0.0, float(modifier))

	if is_critical:
		subtotal *= maxf(1.0, critical_multiplier)

	subtotal *= resistance_multiplier(resistance, penetration)
	subtotal *= maxf(0.0, 1.0 + conditional_extra)
	return subtotal


static func resistance_multiplier(resistance: float, penetration: float) -> float:
	var effective_resistance := clampf(
		resistance - maxf(0.0, penetration),
		MIN_RESISTANCE,
		MAX_RESISTANCE
	)
	return 1.0 - effective_resistance


static func effective_haste(raw_haste: float, soft_cap: float = 1.0) -> float:
	var safe_haste := maxf(0.0, raw_haste)
	var safe_cap := maxf(0.01, soft_cap)
	return safe_haste / (1.0 + safe_haste / safe_cap)


static func interval_after_haste(base_interval: float, raw_haste: float) -> float:
	return maxf(0.02, base_interval) / (1.0 + effective_haste(raw_haste))


static func rolls_critical(rng: RandomNumberGenerator, chance: float) -> bool:
	return rng.randf() < clampf(chance, 0.0, MAX_CRITICAL_CHANCE)
