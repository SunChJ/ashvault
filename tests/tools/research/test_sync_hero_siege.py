import base64
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.research.sync_hero_siege import (
    ArtifactManifest,
    decode_sveltekit_payload,
    normalize_build_payloads,
)
from tools.research.analyze_hero_siege import (
    classify_progression_stage,
    summarize_gear_recommendations,
)


class SvelteKitPayloadTests(unittest.TestCase):
    def test_decodes_flattened_guide_and_date(self) -> None:
        payload = {
            "type": "data",
            "nodes": [
                None,
                {
                    "type": "data",
                    "data": [
                        {"guide": 1},
                        {"slug": 2, "updatedAt": 3, "sections": 5},
                        "s10-example",
                        ["Date", "2026-08-30T02:41:09.937Z"],
                        None,
                        [6],
                        {"data": 7},
                        {"build": 8},
                        "W10=",
                    ],
                },
            ],
        }

        decoded = decode_sveltekit_payload(payload)

        self.assertEqual(decoded["guide"]["slug"], "s10-example")
        self.assertEqual(decoded["guide"]["updatedAt"], "2026-08-30T02:41:09.937Z")
        self.assertEqual(decoded["guide"]["sections"][0]["data"]["build"], "W10=")

    def test_rejects_payload_without_page_data(self) -> None:
        with self.assertRaisesRegex(ValueError, "page data"):
            decode_sveltekit_payload({"type": "data", "nodes": [None]})


class BuildPayloadTests(unittest.TestCase):
    def test_decodes_nested_build_tree_and_talents(self) -> None:
        encoded = base64.b64encode(
            json.dumps([3, None, "", ["skill", 20]], separators=(",", ":")).encode()
        ).decode()
        source = {
            "tabs": [
                {"build": encoded},
                {"tree": encoded},
                {"talents": encoded},
            ]
        }

        normalized = normalize_build_payloads(source)

        for key, tab in zip(("build", "tree", "talents"), normalized["tabs"]):
            self.assertEqual(tab[f"{key}_decoded"], [3, None, "", ["skill", 20]])
            self.assertEqual(tab[key], encoded)

    def test_leaves_invalid_payload_untouched(self) -> None:
        self.assertEqual(normalize_build_payloads({"build": "not-base64"}), {"build": "not-base64"})


class ArtifactManifestTests(unittest.TestCase):
    def test_records_content_hash_and_relative_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact_path = root / "raw" / "example.json"
            artifact_path.parent.mkdir(parents=True)
            artifact_path.write_bytes(b'{"ok":true}\n')

            manifest = ArtifactManifest(root)
            manifest.add(
                source_id="example",
                kind="json",
                source_url="https://example.test/data.json",
                path=artifact_path,
            )

            artifact = manifest.artifacts[0]
            self.assertEqual(artifact["path"], "raw/example.json")
            self.assertEqual(artifact["bytes"], 12)
            self.assertEqual(
                artifact["sha256"],
                hashlib.sha256(b'{"ok":true}\n').hexdigest(),
            )


class ReferenceAnalysisTests(unittest.TestCase):
    def test_classifies_progression_labels(self) -> None:
        self.assertEqual(classify_progression_stage("Early campaign"), "early")
        self.assertEqual(classify_progression_stage("Mid Game"), "mid")
        self.assertEqual(classify_progression_stage("Aspirational"), "late")
        self.assertEqual(classify_progression_stage("Alternative"), "other")

    def test_summarizes_equipment_and_excludes_consumables(self) -> None:
        codex = {
            "named_helm": {"rarity": "Heroic", "type": "Helmet"},
            "healing": {"rarity": "Common", "type": "Consumable"},
        }
        guides = [
            {
                "guide": {
                    "sections": [
                        {
                            "kind": "gear",
                            "data": {
                                "tabs": [
                                    {
                                        "label": "Late",
                                        "build_decoded": [
                                            3,
                                            None,
                                            "",
                                            [],
                                            [
                                                ["helm", "named_helm"],
                                                ["potion1", "healing"],
                                            ],
                                        ],
                                    }
                                ]
                            },
                        }
                    ]
                }
            }
        ]

        summary = summarize_gear_recommendations(guides, codex)

        self.assertEqual(summary["late"]["total"], 1)
        self.assertEqual(summary["late"]["rarities"]["Heroic"], 1)


if __name__ == "__main__":
    unittest.main()
