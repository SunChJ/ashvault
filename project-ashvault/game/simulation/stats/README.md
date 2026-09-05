# Stat Resolution

`StatRegistry` publishes immutable stat definitions. `StatModifier` represents
one configured source contribution. `StatResolver` validates the complete input
and produces an immutable, explainable `StatSnapshot` for one simulation tick.

Consumers never calculate final values independently. Condition evaluation
happens outside this module; the resolver receives active stable condition IDs
and records applied or skipped provenance.


## Authored modifier templates

`StatModifierTemplate` is the shared frozen Resource for authored numeric effects
with `stat_effect.*` IDs. It constructs the existing immutable StatModifier,
optionally scaling its numeric amount. ItemStatEffect retains the original item
Resource path/fields and overrides the ID prefix to `item_effect.*`. Character
passives reuse the same template and resolver without importing item contracts.
