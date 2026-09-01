# Stat Resolution

`StatRegistry` publishes immutable stat definitions. `StatModifier` represents
one configured source contribution. `StatResolver` validates the complete input
and produces an immutable, explainable `StatSnapshot` for one simulation tick.

Consumers never calculate final values independently. Condition evaluation
happens outside this module; the resolver receives active stable condition IDs
and records applied or skipped provenance.
