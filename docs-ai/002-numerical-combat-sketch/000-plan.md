# 002 — Numerical Combat Sketch: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-01 |
| **Primary refs** | [`001-action.md`](001-action.md) |
| **Related** | [`project-ashvault/`](../../project-ashvault/), [`research/hero-siege/`](../../research/hero-siege/) |

## Background

Ashvault needs a playable numerical sketch before content production. The
prototype must test whether its damage layers, experience cadence, skill growth,
enemy density, and power spikes create a satisfying ARPG loop.

Hero Siege is useful as a structural reference. Its documented attacker formula
separates weapon base, enhanced damage, flat damage, attack damage, critical
strike, armor break, conditional extra damage, and skill scaling. Its caster
formula separates skill-level base damage, flat skill damage, synergies,
magic/element damage, resistance, and conditional multipliers. Its Hero Level
experience curve uses visible slope changes rather than one unbroken exponent.

The source pages are community documentation and may lag the current game.
Ashvault inherits the useful shape, not exact constants or undocumented rules.

## Goals

- Implement a pure, testable numerical kernel for damage, haste, experience,
  and skill growth.
- Build a playable top-down arena sketch using only procedural visuals.
- Reach meaningful power changes within a 12–15 minute observation window.
- Make skill ranks change behavior at milestones, not only increase damage.
- Create frequent early upgrades, slower mid-run choices, elites, bosses, and a
  temporary overdrive state that produces clear kill-density peaks.
- Keep simulation state independent from presentation assets.

### Non-goals

- Production combat, item generation, save data, networking, final classes, or
  final balance.
- A direct Hero Siege formula or content clone.
- Art, animation, audio, procedural maps, inventory, or loot rarity gameplay.
- Compatibility guarantees for the prototype scene or tuning constants.

## Design / Approach

### Numerical kernel

Damage resolves in explicit stages:

```text
base = weapon_or_skill_base * (1 + enhanced) + flat
increased = 1 + sum(increased modifiers)
more = product(more modifiers)
crit = 1 or critical multiplier
mitigation = resistance / penetration result
conditional = 1 + sum(active conditional damage)
final = base * increased * more * crit * mitigation * conditional
```

Haste uses a saturating transform before reducing an interval. Raw haste always
helps, but additional investment past the soft cap has diminishing marginal
value.

Experience uses three piecewise regions. The sketch intentionally compresses
the curve: early levels establish the build quickly, the middle tests choices,
and later levels require density and synergy rather than passive waiting.

Skill rank damage grows mildly convex. Rank milestones add projectiles, chains,
or area changes so a level-up can create an immediately visible clear-speed
spike.

### Playable loop

- WASD / arrow movement with automatic targeting and casting.
- XP shards drop from enemies and magnetize near the player.
- Every level pauses combat and offers three keyboard-selected upgrades.
- Fodder, elite, and boss health occupy distinct time-to-kill bands.
- Consecutive kills trigger temporary Overdrive with increased action speed.
- A charge-based nova produces periodic screen-clearing release moments.
- The run is endless so tuning can be observed beyond the intended window.

### Initial target bands

| Signal | Target |
| --- | --- |
| First upgrade | 8–15 seconds |
| Early level interval | 10–25 seconds |
| Mid-run level interval | 25–50 seconds |
| Fodder TTK | 0.2–0.8 seconds |
| Elite TTK | 3–6 seconds |
| Boss TTK | 12–25 seconds |
| First behavior-changing skill milestone | Before 90 seconds |
| Comfortable live enemy density | 30–120 |

These are prototype hypotheses, not product contracts.

## Architecture

- `prototype/core/combat_math.gd`: stateless damage and timing formulas.
- `prototype/core/progression_math.gd`: experience and skill rank curves.
- `prototype/numerical_sketch.gd`: arena simulation and procedural rendering.
- `prototype/numerical_sketch.tscn`: runnable composition root.
- `tests/test_numerical_core.gd`: headless numerical invariants.

The prototype uses a single simulation owner and compact state arrays instead
of one physics node per projectile or enemy. This preserves a path toward the
simulation/presentation boundary already chosen for the ARPG kernel.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Copy Hero Siege constants | Rejected: source versions and Ashvault pacing differ. |
| Start with item drops | Deferred: combat and progression cadence must work before item variance. |
| Build a spreadsheet-only model | Rejected: it cannot validate movement, target pressure, or perceived power spikes. |
| Use one Node2D per entity | Rejected for the sketch: compact simulation state better represents the density target. |
| Add production abstractions now | Rejected: formulas are stable candidates; encounter content remains disposable. |

## Risks

- A procedural visual sketch can validate cadence but not final audiovisual
  impact.
- Auto-targeting reduces input complexity and may overstate the final combat
  feel.
- Community formulas are references, not verified current Hero Siege source
  code.
- A 12–15 minute curve cannot validate long-term progression or economy.

## Validation

- Run headless formula and curve tests with Godot 4.7.2.
- Import and execute the main scene headlessly to catch parse/runtime failures.
- Run deterministic balance sampling and inspect level cadence, TTK, and power
  milestone outputs.
- Verify the project starts in the numerical sketch scene.

## Amendments
