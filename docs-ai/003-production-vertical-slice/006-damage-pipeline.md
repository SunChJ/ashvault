# 003.006 — Unified Damage Pipeline

## Context

Stats, abilities, items, statuses, and enemies need one deterministic path from
hit inputs to committed health damage. M1-03 establishes that path before event
processing and ability execution can depend on combat results.

## Change

Every hit is described by an immutable `DamageContext` containing runtime
entity/event IDs, a stable ability ID, tags, base components, damage modifiers,
active conditions, and an externally supplied critical roll. The damage
pipeline is scene-independent and never owns randomness.

Resolution follows the Kernel contract exactly:

1. Sum base components and flat modifiers by damage type.
2. Apply one additive increased bucket per type.
3. Apply more multipliers in stable priority/source order.
4. Apply conversions simultaneously from pre-conversion values, reserving at
   most 100% of each source type.
5. Apply the critical multiplier once when the supplied roll succeeds.
6. Apply defense with `100 / (100 + defense)` diminishing returns.
7. Apply resistance and penetration with the inherited effective-resistance
   range `[-1.0, 0.85]`.
8. Apply active conditional modifiers in stable order.
9. Clamp each final component to non-negative finite damage.

The prototype's critical cap (`0.95`), resistance bounds, penetration behavior,
and additive-increased/multiplicative-more shapes are retained. Defense is a
new, separate mitigation stage because the numerical sketch did not model it.

`DamageResult` owns a deep-copied stage breakdown for every damage type,
mitigation deltas, critical state, and sorted contributing source IDs. It keeps
the resolved total as floating point. `committed_amount()` rounds only the
summed final total, defining the sole boundary where damage becomes an integer
health delta. Negative inputs can reduce a component to zero but can never
become healing.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| Let callers pre-roll each component | Rejected because rounding drift would make split damage behave differently. |
| Let the pipeline draw random values | Rejected because it would hide combat-stream consumption and weaken replay isolation. |
| Mutate converted components sequentially | Rejected because input order could create accidental conversion chains. |
| Put damage arithmetic in abilities or items | Rejected because ordering, mitigation, and provenance would diverge. |
| Reuse the prototype implementation at runtime | Rejected because production and prototype boundaries are intentionally isolated. |

## Validation

- Lock the public stage order and the inherited formula boundaries.
- Test base/flat/increased/more/conversion/critical/defense/resistance/
  penetration/conditional/clamp resolution with exact expected values.
- Test stable conversion arbitration with reversed modifier input.
- Test negative final damage clamps to zero and cannot become healing.
- Test split fractional components round only after their final sum.
- Test invalid contexts fail transactionally without a partial result.
- Test returned breakdowns cannot mutate the published result.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-03. The unified suite
passes with 33 Python tests, seven production GDScript contract suites,
performance report validation, prototype regressions, and the main-scene smoke
test. The linked PR and #9 remain the authoritative delivery state.
