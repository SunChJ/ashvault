# Hero Siege Reference Findings

## Direct conclusion

The supplied concern is visible in the current Season 10 reference data: named
high-tier equipment dominates both community build payloads and the available
item catalogs. Ashvault should not copy this replacement ladder or its planner
representation.

Across 18 public Season 10 guides, 275 non-consumable late-stage equipment
recommendations were decoded and joined to the `hs-map` codex with no missing
IDs:

| Rarity | Recommendations | Share |
| --- | ---: | ---: |
| Heroic | 179 | 65.1% |
| Angelic | 43 | 15.6% |
| Satanic | 17 | 6.2% |
| Satanic Set | 13 | 4.7% |
| Unholy | 12 | 4.4% |
| Runeword | 11 | 4.0% |

The five named high-tier categories account for 96.0% of late-stage equipment
recommendations. No arbitrary randomized magic, rare, or monster-specific item
can be represented by these payloads.

A sensitivity check removed transitional labels containing `early` or `mid`.
The remaining 247 recommendations still measured 96.0% named high-tier, so the
headline result is not caused by those ambiguous stage labels.

The Wiki Cargo named-item catalog shows the same concentration but has a
different scope: 416 of 912 rows are Satanic and 227 are Satanic Set. This is a
named-item table, not a distribution of generated drops, so it supports a
catalog-shape conclusion rather than a drop-rate conclusion.

## Interpretation

Two effects reinforce each other:

1. Hero Siege endgame progression rewards replacement by fixed high-tier named
   items.
2. Community planners encode a build slot as an exact item ID. They cannot
   communicate "any green base with these two affixes and this roll floor."

The second effect makes community knowledge and guide authoring even more
unique-centric. Ashvault's planner must avoid this representational bias.

## Ashvault item-system requirements

- Rarity controls generation rules, affix budget, and acquisition shape; it
  does not impose a universal power ceiling.
- Common bases retain scarcity through base implicits, quality, sockets,
  runeword eligibility, and crafting potential.
- Magic items provide focused stat identity through fewer affixes, higher
  individual roll ceilings, or deterministic modification.
- Rare items provide broad multi-affix flexibility and difficult emergent
  combinations.
- Monster-specific items combine a deterministic base identity with random
  affixes and remain target-farmable endgame candidates.
- Epic items own narrow, reliable interactions that may remain optimal.
- Top-tier uniques and sets change rules or enable builds. They should compete
  with excellent generated items instead of replacing them categorically.
- Investment systems must preserve value across rarity bands rather than
  reserving all upgrade depth for named top-tier items.

## Planner representation

A slot should accept either an exact named item or a candidate specification:

```json
{
  "slot": "weapon",
  "base_requirements": ["one_handed", "caster"],
  "required_affixes": [
    { "stat": "lightning_skill_levels", "minimum": 3 }
  ],
  "preferred_affixes": [
    { "stat": "cast_speed", "weight": 1.0 },
    { "stat": "lightning_penetration", "weight": 0.8 }
  ],
  "allowed_rarities": ["magic", "rare", "monster_specific", "unique"],
  "socket_requirements": { "minimum": 2 },
  "crafting_state": "upgradeable",
  "named_item_alternatives": []
}
```

This representation can later power item search, loot filters, guide authoring,
drop simulation, and a build optimizer from the same model.

## Content shape

The current direction is a four-act compressed campaign. Hero Siege remains a
useful structural reference for repeatable dungeons, Codex-like modifiers,
target farming, and seasonal content, but individual mechanics must be selected
for how they interact with Ashvault's item and build systems rather than copied
as content volume.

## Evidence limits

- Guide stage labels are author-provided and classified heuristically.
- Planner payloads describe recommendations, not player inventories or actual
  item usage.
- Community data may lag patches and can disagree with game files.
- Public access is not a redistribution license; raw and normalized snapshots
  remain under ignored `.research/` storage.
