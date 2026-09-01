# 003.005 — Stat Resolution and Immutable Snapshots

## Context

Damage, abilities, items, entities, and UI need one deterministic stat result
rather than subsystem-specific arithmetic. M1-02 establishes the registry,
modifier vocabulary, ordering, conversion arbitration, conditional provenance,
and per-tick immutable output consumed by later kernel tasks.

## Change

`StatRegistry` transactionally publishes immutable stat definitions with stable
IDs and default values. `StatResolver` accepts that registry, configured
modifiers, active condition IDs, and a simulation tick, then either returns all
validation errors with no snapshot or one immutable `StatSnapshot`.

Resolution semantics are:

1. Registry default plus all `BASE` values.
2. Add all `FLAT` values.
3. Multiply once by `1 + sum(INCREASED)`.
4. Multiply by each `1 + MORE` value in stable order.
5. Apply conversions simultaneously from the pre-conversion values.
6. Apply the winning `OVERRIDE`.
7. Apply `CAP` maximum constraints.

Modifiers sort by descending numeric priority, then ascending `source_id`.
One source may contribute at most one modifier for a stat, operation, and
condition; duplicates are rejected so input order cannot break ties.

Conversion modifiers name a source stat and target stat. They reserve their
requested fraction in stable order, limited by the source's remaining 100%
allocation. Incoming converted values do not convert again in the same stage.
This preserves simultaneous, non-cascading resolution and makes
over-allocation deterministic.

An explanation records every applied source, inactive conditional source,
shadowed override, conversion allocation, and incoming conversion. Snapshots
copy numeric values and explanation DTOs; callers never receive mutable backing
storage or modifier references.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| Let items/skills calculate final stats | Rejected because ordering and provenance would diverge across systems. |
| Apply conversion mutations sequentially | Rejected because input order could create accidental conversion chains. |
| Treat priority as insertion order | Rejected because replay results must not depend on collection construction. |
| Store only final numbers | Rejected because conditional and conversion sources must remain explainable. |
| Add a general expression language now | Rejected; M1-02 accepts resolved condition IDs and leaves condition evaluation to later systems. |

## Validation

- Test registry publication, invalid definitions, and duplicate IDs.
- Test all seven operations and exact stage order.
- Test conversion over-allocation, simultaneous conversion, and stable source
  ordering with reversed input.
- Test active/inactive conditional provenance and shadowed overrides.
- Test invalid modifiers fail without a partial snapshot.
- Test returned value and explanation dictionaries cannot mutate the snapshot.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-02. The unified suite
passes with 33 Python tests, six production GDScript contract suites,
performance report validation, prototype regressions, and the main-scene smoke
test. No planned ordering or ownership deviation was required. The linked PR
and #8 remain the authoritative delivery state.
