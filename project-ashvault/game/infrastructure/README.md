# Infrastructure

Owns composition roots, catalog loading, persistence adapters, export wiring,
and integration with developer tooling.

Infrastructure coordinates production modules without absorbing their rules or
referencing `res://prototype/`.

`PerformanceMetrics` owns the scene-independent aggregation contract for
headless simulation timing and entity-count reports. Benchmark orchestration
lives under `tools/performance/`; it must advance simulation directly and never
depend on rendered frames.

`HeadlessCombatSimulation` is the infrastructure composition root for
deterministic combat replay. It advances the production kernel without loading
a scene and publishes deterministic combat/state evidence separately from
wall-clock measurements gathered by `PerformanceMetrics`.
