# Hero Siege Reference Research

This directory defines how Ashvault studies Hero Siege without making Hero
Siege data part of the game or repository.

## Product conclusions

Hero Siege is a strong reference for combat density, item-driven builds,
dungeons, seasonal systems, and long-term content operations. It is not the
target model for item rarity value. Ashvault must preserve meaningful endgame
roles across rarity bands:

| Band | Durable role |
| --- | --- |
| Common base | Base identity, sockets, runewords, deterministic crafting, and scarce ideal bases. |
| Magic | Fewer but more focused affixes, stronger individual rolls, or lower crafting entropy. |
| Rare | Flexible multi-affix combinations with a high emergent ceiling. |
| Monster-specific | Farmable identity plus random affixes; build-defining equivalents to Grim Dawn's Monster Infrequents. |
| Epic | Reliable niche or bridge item that can remain optimal for a narrow interaction. |
| Top-tier unique / set | Rule transformation and build enablement, not universal best-in-slot status. |

Item value should be modeled as a combination of base, affix synergy, roll
quality, crafting potential, availability, and special identity. Rarity alone
must not determine replacement order.

The campaign should be compressed into four acts. Repeatable dungeons and
selected seasonal mechanics provide the long-tail structure after the main
story.

The local planner must represent randomized equipment candidates, not only
named item IDs. A slot recommendation needs base constraints, required and
preferred affixes, roll thresholds, sockets, and crafting state, with a named
unique as one optional candidate. See [`FINDINGS.md`](FINDINGS.md) for the
evidence and current implications.

## Sources

- [MisterSleepyCat map](https://mistersleepycat.info/map): zones, bosses, and
  drop relationships via the linked `Parazeya/hs-map` project.
- [MisterSleepyCat item codex](https://mistersleepycat.info/map/codex): item and
  stat reference data.
- [MisterSleepyCat guides](https://mistersleepycat.info/guides/s10-stormweaver):
  progression stages, attributes, skill trees, incarnation trees, gear, and
  encoded planner payloads.
- [Hero Siege Helper](https://hero-siege-helper.vercel.app/): items, affixes,
  bases, abilities, dungeons, trees, formulas, seasons, and related tools.
- Hero Siege Wiki Cargo exports used by Hero Siege Helper for structured item
  and stat records.

See [`sources.json`](sources.json) for the exact machine-readable endpoints and
current reuse-policy notes.

## Local synchronization

```bash
python3 tools/research/sync_hero_siege.py
python3 tools/research/analyze_hero_siege.py
```

The command writes to `.research/hero-siege/`, which is intentionally ignored
by Git. The output contains:

```text
.research/hero-siege/
├── manifest.json
├── raw/
│   ├── upstreams/hs-map/
│   ├── mistersleepycat/
│   ├── hero-siege-helper/
│   └── hero-siege-wiki/
└── normalized/
    ├── guides/
    ├── guides-index.json
    ├── helper-pages-index.json
    └── hs-map-summary.json
```

Normalized guides preserve the original encoded `build`, `tree`, and `talents`
fields and add decoded siblings such as `build_decoded`. This is sufficient to
inspect and later prototype a local planner without treating the upstream
format as Ashvault's save or build schema.

## Boundary

External source IDs belong only to reference entities described by
[`reference-model.schema.json`](reference-model.schema.json). Ashvault game
definitions require independent identifiers and explicit design decisions.
Third-party raw data, code, art, and prose must not be committed without a
separate licensing review.
