#!/usr/bin/env python3
"""Measure item-value concentration in the local Hero Siege reference snapshot."""

from __future__ import annotations

import argparse
import json
import os
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPOSITORY_ROOT / ".research" / "hero-siege"
NAMED_HIGH_TIERS = {"Angelic", "Heroic", "Satanic", "Satanic Set", "Unholy"}
CONSUMABLE_TYPES = {"Consumable", "Potion"}


def write_json(path: Path, value: Any) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)
    return path


def classify_progression_stage(label: str) -> str:
    normalized = label.strip().lower()
    if any(token in normalized for token in ("late", "endgame", "aspirational")):
        return "late"
    if "mid" in normalized:
        return "mid"
    if any(token in normalized for token in ("early", "start", "level")):
        return "early"
    return "other"


def _gear_pairs(build: Any) -> Iterable[List[Any]]:
    if not isinstance(build, list) or len(build) <= 4 or not isinstance(build[4], list):
        return []
    return (
        pair
        for pair in build[4]
        if isinstance(pair, list) and len(pair) >= 2
    )


def summarize_gear_recommendations(
    guides: Iterable[Dict[str, Any]], codex: Dict[str, Dict[str, Any]]
) -> Dict[str, Any]:
    rarity_counts: Dict[str, Counter[str]] = defaultdict(Counter)
    missing_item_ids: Counter[str] = Counter()

    for payload in guides:
        for section in payload.get("guide", {}).get("sections", []):
            if section.get("kind") != "gear":
                continue
            for tab in (section.get("data") or {}).get("tabs", []):
                stage = classify_progression_stage(str(tab.get("label", "")))
                for slot, item_id, *_ in _gear_pairs(tab.get("build_decoded")):
                    item = codex.get(str(item_id))
                    if item is None:
                        missing_item_ids[str(item_id)] += 1
                        continue
                    if str(slot).startswith("potion") or item.get("type") in CONSUMABLE_TYPES:
                        continue
                    rarity_counts[stage][str(item.get("rarity", "Unknown"))] += 1

    result: Dict[str, Any] = {}
    for stage in ("early", "mid", "late", "other"):
        counts = rarity_counts[stage]
        total = sum(counts.values())
        named_high_tier = sum(counts[rarity] for rarity in NAMED_HIGH_TIERS)
        result[stage] = {
            "total": total,
            "rarities": dict(counts.most_common()),
            "rarity_percentages": {
                rarity: round(count * 100 / total, 1) if total else 0.0
                for rarity, count in counts.most_common()
            },
            "named_high_tier": named_high_tier,
            "named_high_tier_percentage": round(named_high_tier * 100 / total, 1)
            if total
            else 0.0,
        }
    result["missing_item_ids"] = dict(missing_item_ids.most_common())
    return result


def analyze(snapshot: Path) -> Dict[str, Any]:
    manifest = json.loads((snapshot / "manifest.json").read_text(encoding="utf-8"))
    codex = json.loads(
        (snapshot / "raw/upstreams/hs-map/public/data/codex.json").read_text(
            encoding="utf-8"
        )
    )["items"]
    guides = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in sorted((snapshot / "normalized/guides").glob("*.json"))
    ]
    wiki_items = json.loads(
        (snapshot / "raw/hero-siege-wiki/items.json").read_text(encoding="utf-8")
    )
    wiki_rarities = Counter(
        str(item.get("Item Rarity") or "Unknown") for item in wiki_items
    )

    return {
        "schema_version": 1,
        "snapshot_generated_at": manifest["generated_at"],
        "guide_count": len(guides),
        "guide_gear_recommendations": summarize_gear_recommendations(guides, codex),
        "wiki_named_item_catalog": {
            "total": len(wiki_items),
            "rarities": dict(wiki_rarities.most_common()),
        },
        "interpretation_limits": [
            "Guide stages are inferred from author-provided tab labels.",
            "The planner payload represents named item IDs and cannot express arbitrary randomized affix rolls.",
            "The Wiki Cargo item table is a named-item catalog, not the population of all generated drops.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--output", type=Path, default=None)
    arguments = parser.parse_args()

    snapshot = arguments.snapshot.resolve()
    output = arguments.output or snapshot / "analysis/item-value-concentration.json"
    result = analyze(snapshot)
    write_json(output, result)
    print(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True))
    print(f"Analysis: {output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
