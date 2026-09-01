# 001 — Hero Siege Reference Data: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-01 | Defined the provenance and redistribution boundary. | [`000-plan.md`](000-plan.md) |
| 2026-09-01 | Implemented and verified local synchronization, guide decoding, and concentration analysis. | Pending commit |

## Outcome & current state (as of 2026-09-01)

The repository now contains a reproducible research workflow while all
third-party snapshots remain ignored under `.research/hero-siege/`.

Key tracked files:

- `tools/research/sync_hero_siege.py`: source synchronization, SvelteKit
  hydration, build decoding, provenance manifest, and upstream Git mirror.
- `tools/research/analyze_hero_siege.py`: reproducible item-value concentration
  analysis.
- `research/hero-siege/sources.json`: exact sources and reuse-policy notes.
- `research/hero-siege/reference-model.schema.json`: provenance-aware external
  reference boundary.
- `research/hero-siege/README.md`: operating instructions and product boundary.
- `research/hero-siege/FINDINGS.md`: evidence-backed item and planner decisions.
- `tests/tools/research/test_sync_hero_siege.py`: parser, manifest, and analysis
  regression coverage.

The verified local snapshot contains:

| Source | Observed records |
| --- | ---: |
| `hs-map` codex items | 1,727 |
| `hs-map` map items | 942 |
| `hs-map` places / bosses | 57 / 35 |
| MisterSleepyCat guides | 18 |
| Decoded build/tree/talent payloads | 340 |
| Hero Siege Helper pages | 42 |
| Wiki items / item stats / stat formats | 912 / 6,155 / 174 |

The late-stage guide sample contains 275 non-consumable equipment
recommendations. Named high-tier categories account for 96.0%; Runewords
account for the remaining 4.0%. This result supports a planner model that can
express randomized item constraints instead of only exact named item IDs.

## Validation

- `python3 -m unittest tests/tools/research/test_sync_hero_siege.py`: 7 tests
  passed.
- `python3 -m py_compile tools/research/sync_hero_siege.py tools/research/analyze_hero_siege.py`: passed.
- Both tracked JSON documents passed `python3 -m json.tool`.
- Live synchronization completed with 93 manifested artifacts and no missing
  Helper pages.
- All file artifact hashes in the generated manifest were recomputed after the
  final run.
- A stricter stage sensitivity check excluded labels containing `early` or
  `mid`; the named high-tier share remained 96.0% across 247 recommendations.
- `.research/` is ignored and no third-party snapshot is staged.

## Deviations from plan

- Hero Siege Helper was added as a second upstream after the initial source
  inspection because it exposes complementary item, affix, base, dungeon, tree,
  and formula material.
- The first live sync exposed two stale navigation assumptions
  (`gearprogression` and `sets`). Their current nested routes were verified, and
  the synchronizer now records expected HTTP 404 responses rather than silently
  treating them as content.
- A separate analysis command was added because item-value concentration is a
  consequential product decision and should remain reproducible.

## Open questions

- Final Ashvault rarity names and the exact Monster Infrequent equivalent.
- Affix-count, roll-ceiling, crafting-cost, and upgrade-budget rules per rarity.
- Which Hero Siege dungeon and seasonal mechanics deserve deeper system-level
  studies after the item kernel is specified.
- Whether the first planner is a headless build schema, a local web tool, or a
  Godot editor/runtime surface.
