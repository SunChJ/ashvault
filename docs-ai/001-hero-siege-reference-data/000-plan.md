# 001 — Hero Siege Reference Data: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-01 |
| **Primary refs** | Pending |
| **Related** | [`research/hero-siege/`](../../research/hero-siege/) |

## Background

Ashvault is a long-lived, data-driven ARPG rather than a direct Hero Siege
clone. Hero Siege provides useful reference material for combat density,
dungeons, seasons, items, trees, and build progression, but its endgame item
economy over-concentrates value in Satanic-tier and set items.

MisterSleepyCat exposes public map, codex, and guide data. Hero Siege Helper
adds item, affix, base, skill, dungeon, tree, and formula references. Their raw
content is useful for private research, but it is not an Ashvault source of
truth and cannot be assumed redistributable.

## Goals

- Create a reproducible local snapshot of public reference sources.
- Preserve source URL, retrieval time, upstream revision, size, and SHA-256.
- Normalize SvelteKit guide payloads and decode embedded build/tree payloads.
- Keep all third-party raw and derived snapshots outside Git.
- Define a provenance-aware reference schema that cannot leak into Ashvault's
  canonical game definitions without an explicit design step.
- Record initial product constraints for item rarity value and content shape.

### Non-goals

- Redistribute Hero Siege code, art, prose, or extracted game data.
- Make external identifiers canonical Ashvault identifiers.
- Implement Ashvault's final item generator, build planner, or combat model.
- Promise compatibility with undocumented upstream formats.
- Mirror administrator routes or bypass access controls.

## Design / Approach

1. Add a standard-library Python synchronizer under `tools/research/`.
2. Clone or fast-forward `Parazeya/hs-map` into ignored local storage. Its
   repository currently has no declared license, so no files are vendored.
3. Read public sitemaps and endpoints while respecting each site's robots
   policy. Use a descriptive user agent and bounded request pacing.
4. Store raw responses under `.research/hero-siege/raw/`.
5. Hydrate MisterSleepyCat's SvelteKit `__data.json` guide payloads, decode
   embedded base64 JSON builds, and store normalized results under
   `.research/hero-siege/normalized/`.
6. Snapshot selected Hero Siege Helper pages and the public wiki Cargo JSON
   endpoints used by the helper. Keep page snapshots raw until a stable
   entity-level parser is justified.
7. Generate a machine-readable manifest for every fetched or generated file.
8. Test parsing and manifest behavior with repository-owned synthetic fixtures;
   network access is not required for unit tests.

The reference model keeps three identities separate:

```text
External source ID -> Reference entity -> Ashvault definition
       observed          normalized          independently designed
```

Every reference entity must retain provenance. Promotion into an Ashvault
definition is a deliberate design action, not an automatic import.

## Product constraints captured by this work

- Rarity is not a monotonic replacement ladder.
- Common bases retain value through base properties, sockets, runewords, or
  deterministic crafting.
- Magic items trade affix count for focus, roll ceiling, or crafting control.
- Rare items provide flexible multi-affix combinations and a high emergent
  ceiling.
- Monster-specific or equivalent green items combine a farmable identity with
  random affixes and may remain build-defining at endgame.
- Epic items occupy reliable niches instead of serving only as temporary trash.
- Top-tier uniques and sets transform rules or enable builds; they are not
  universally best in slot. Partial set use should remain viable.
- The campaign targets four compressed acts. Dungeons and seasonal mechanics
  carry most repeatable and long-tail content.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Commit a full website mirror | Rejected: unnecessary repository weight and unclear redistribution rights. |
| Add `hs-map` as a Git submodule | Rejected for now: no declared license and no need to couple product checkout to research data. |
| Scrape rendered DOM only | Rejected: structured SvelteKit and Cargo payloads are more stable and inspectable. |
| Treat upstream schemas as the game schema | Rejected: it would couple Ashvault to another game's implementation and identifiers. |

## Risks

- Undocumented SSR formats may change; failures must be explicit and must not
  silently retain a misleading "fresh" status.
- Community sources can disagree or lag the current season. Provenance and
  snapshot timestamps are mandatory.
- Public accessibility is not a redistribution license. Raw data stays ignored.

## Validation

- Run parser unit tests.
- Run a real synchronization against all configured sources.
- Validate generated JSON and manifest hashes.
- Confirm `.research/` remains ignored and no third-party snapshot is staged.

## Amendments
