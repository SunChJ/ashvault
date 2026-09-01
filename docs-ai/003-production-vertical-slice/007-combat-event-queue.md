# 003.007 — Queued Combat Events and Proc Guards

## Context

Damage results, abilities, statuses, and items need to publish reactions without
recursively executing gameplay code. M1-04 establishes deterministic event
identity, expansion order, and bounded proc-chain behavior before ability
effects are introduced.

## Change

Callers submit immutable `CombatEventRequest` values. `CombatEventQueue` is the
only publisher of `CombatEvent` values and assigns monotonically increasing
event IDs. A root event begins a chain whose `chain_id` equals its event ID;
children retain the chain ID and increment depth.

The queue processes events FIFO. A handler returns configured
`CombatEventEmission` values rather than invoking child handlers directly. The
queue sorts emissions by descending priority, ascending stable trigger ID, then
ascending explicit sequence before assigning child event IDs. Duplicate
trigger/sequence identities from one parent are rejected. This makes proc order
independent of handler collection order while preserving authored effect order.

Each child carries an internal trigger trace. A trigger already present in that
chain trace cannot emit again unless the emission explicitly enables
`allow_self_reentry`. Root depth is zero; depth eight is processable, but an
attempt to create depth nine is denied. Both guards emit structured diagnostics
without recursively invoking gameplay code.

The default per-tick processing budget is 4096 events. Exhaustion returns a
failed process result with a structured diagnostic and leaves pending events
intact for inspection or deterministic recovery. It never silently drops
events. Invalid handlers or emissions also fail the process result. Guarded
self-reentry and depth denials are expected bounded outcomes and do not by
themselves fail an otherwise drained tick.

Event payloads accept only deeply copied, finite JSON-compatible values with
string keys. This prevents runtime objects, callables, or shared mutable state
from crossing the event boundary. The core event type constants are cast, hit,
critical, damage, status applied, death, kill, block, dodge, item dropped, and
item picked up.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| Invoke proc handlers recursively | Rejected because cycles can overflow the stack and bypass depth/budget accounting. |
| Let handlers enqueue children directly | Rejected because ordering and event identity would depend on caller behavior. |
| Sort only by insertion order | Rejected because unordered trigger collection would change replay results. |
| Drop pending events when budget is reached | Rejected because silent loss hides invalid content and breaks deterministic diagnosis. |
| Store arbitrary Variant payloads | Rejected because mutable Objects and non-finite values cannot form a stable replay boundary. |

## Validation

- Test root identity, chain inheritance, depth, and immutable payload copies.
- Test on-hit, on-critical, and on-kill queue expansion without recursion.
- Test stable priority/trigger/sequence ordering with reversed handler output.
- Test default self-reentry denial and explicit re-entry allowance.
- Test depth-eight processing and depth-nine rejection diagnostics.
- Test budget exhaustion fails with pending events retained.
- Test invalid handler output fails without silently accepting emissions.
- Run the unified local suite and macOS/Windows CI matrix.

## Current state

Implementation and local validation are complete for M1-04. The unified suite
passes with 33 Python tests, eight production GDScript contract suites,
performance report validation, prototype regressions, and the main-scene smoke
test. An editor scan also completed UID coverage for all 39 GDScript files so a
fresh editor checkout remains clean. The linked PR and #10 remain the
authoritative delivery state.
