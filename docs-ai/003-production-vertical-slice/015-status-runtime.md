# 003.015 — Deterministic Status Runtime

## Context

M2-04 needs data-defined status identity, duration constraints, stacking,
refresh, immunity, removal, and exact tick expiry. Shock must enter the existing
damage pipeline as a normal modifier, and status events must enter the existing
combat event queue so its depth, re-entry, and budget guards remain authoritative.

## Planned change

Add a `StatusWorld` configured from immutable `StatusDefinition` resources. The
world receives immutable target snapshots plus application/removal mutations at
the kernel's fixed tick boundary. It validates the complete batch, expires old
states, orders mutations by globally increasing mutation ID, and commits only
after deterministic resolution.

Definitions own:

- stable identity and tags;
- minimum/maximum application duration;
- maximum stacks and additive/replace/maximum stack policy;
- keep/reset/extend refresh policy;
- cleansable/protected removal policy;
- optional conditional damage-modifier templates.

Applications carry the duration and stack values authored by the ability effect.
The definition validates their allowed range and owns how repeat applications
combine. Active state retains only scalar IDs, stack count, expiry tick, and
source/application provenance. One mutation watermark prevents replay without
retaining an unbounded mutation history.

Successful applications publish configured `event.status_applied` requests.
Callers enqueue them as roots in `CombatEventQueue`; the status runtime does not
publish events recursively or bypass proc guards. Active status IDs become the
damage context's conditions. Shock definitions materialize ordinary conditional
`DamageModifier` values scaled by the current stack count, so no alternate damage
formula is introduced.

## Integration boundary

M2-06 translates `AbilityEffectCommand` status fields into `StatusApplication`.
`StatusWorld` does not mutate entity health, resolve damage, or own presentation.
Godot State Charts may mirror a low-count status for animation/UI, but it must not
own duration, stacks, immunity, cleanse, or expiration. Gloot has no status
runtime responsibility.

## Alternatives

| Alternative | Decision |
| --- | --- |
| One Timer/StateChart per active status | Rejected: SceneTree timing would become authoritative and scale with active effects. |
| Apply Shock directly inside damage arithmetic | Rejected: it would create a second formula path outside `DamagePipeline`. |
| Let statuses invoke proc handlers | Rejected: recursive reactions would bypass `CombatEventQueue` guards. |
| Retain every mutation ID for deduplication | Rejected: long sessions would grow state without bound. |

## Validation

- Test application, exact duration boundaries, stacking, refresh, and expiry.
- Test status-ID and tag immunity without partial state changes.
- Test cleansable and protected removal policies.
- Test Shock through a conditional `DamageModifier` and `DamagePipeline`.
- Test status-applied events through self-reentry guards in `CombatEventQueue`.
- Test invalid batches, mutation-order invariance, canonical state hashing, and
  replay equality.
- Run the editor scan, unified local suite, and macOS/Windows CI matrix.

## Current state

Implemented for #18. Immutable definitions and modifier templates feed a
transactional `StatusWorld` with scalar active state, exact expiry, all declared
stack/refresh policies, exact-ID and tag immunity, cleansable/protected removal,
forced cleanup after target loss, and a bounded mutation watermark.

Focused tests cover application, stack caps, replace/add/maximum policies,
keep/reset/extend refresh, expiration, immunity, cleanse, protected and forced
removal, rollback, mutation-order invariance, frozen state hashing, Shock through
`DamagePipeline`, and status event self-reentry through `CombatEventQueue`. Full
local and CI results are recorded in the status PR.
