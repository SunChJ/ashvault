# AI Documentation

`docs-ai/` is this project's curated engineering memory. It records why
substantial features, architecture choices, and decision-shaping fixes exist,
together with what was ultimately implemented.

This directory is not a task journal. Current-state contributor documentation
belongs under `docs/` or the repository's established documentation tree;
`docs-ai/` preserves plans, implementation outcomes, amendments, and living
engineering runbooks that future humans and agents need to make sound changes.

## Entry model

Each substantial topic uses a three-digit numbered directory:

```text
docs-ai/NNN-kebab-case-topic/
├── 000-plan.md
├── 001-action.md
└── 002-follow-up.md
```

- `000-plan.md` is written before implementation and captures goals, non-goals,
  design, and rejected alternatives.
- `001-action.md` records the verified outcome and deviations from the plan.
- `002-*.md` and later numbered files record meaningful follow-ups.
- Non-numbered files inside an entry are living references or runbooks and are
  updated in place.

Use the project skill at `.claude/skills/write-ai-doc/SKILL.md` for selection,
writing, amendment, and verification rules.

## Index

| ID | Topic | Anchor date | Summary |
| --- | --- | --- | --- |
| [001](001-hero-siege-reference-data/000-plan.md) | Hero Siege reference data | 2026-09-01 | Reproducible, provenance-aware local research snapshots without vendoring third-party content. |
| [002](002-numerical-combat-sketch/000-plan.md) | Numerical combat sketch | 2026-09-01 | Playable damage, experience, skill-growth, density, and power-spike prototype. |
| [003](003-production-vertical-slice/000-plan.md) | Production vertical slice | 2026-09-01 | Kernel-first active-ARPG slice with persistent loot, modular dungeon, and gated execution tasks. |
