from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT_ROOT = REPOSITORY_ROOT / "project-ashvault"
PRODUCTION_ROOT = PROJECT_ROOT / "game"
PROTOTYPE_ROOT = PROJECT_ROOT / "prototype"
REQUIRED_ROOTS = (
    "simulation",
    "content",
    "presentation",
    "infrastructure",
)
SCANNED_SUFFIXES = {".cs", ".gd", ".gdshader", ".tres", ".tscn"}
PROTOTYPE_REFERENCE = re.compile(r"(?:res://|(?:\.\./)+)prototype/")
PRODUCTION_REFERENCE = re.compile(r"(?:res://|(?:\.\./)+)game/")


class ProductionBoundaryTests(unittest.TestCase):
    def test_required_production_roots_exist(self) -> None:
        for root_name in REQUIRED_ROOTS:
            with self.subTest(root=root_name):
                root = PRODUCTION_ROOT / root_name
                self.assertTrue(
                    root.is_dir(),
                    f"Missing production root: game/{root_name}",
                )
                self.assertTrue(
                    (root / "README.md").is_file(),
                    f"Missing ownership documentation: game/{root_name}/README.md",
                )

    def test_production_files_do_not_reference_prototype(self) -> None:
        violations: list[str] = []
        if not PRODUCTION_ROOT.is_dir():
            self.fail("Missing production root: project-ashvault/game")

        for path in sorted(PRODUCTION_ROOT.rglob("*")):
            if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
                continue
            contents = path.read_text(encoding="utf-8")
            if PROTOTYPE_REFERENCE.search(contents):
                violations.append(str(path.relative_to(REPOSITORY_ROOT)))

        self.assertEqual(
            violations,
            [],
            "Production files must not reference prototype assets or scripts.",
        )

    def test_prototype_files_do_not_reference_production(self) -> None:
        violations: list[str] = []
        for path in sorted(PROTOTYPE_ROOT.rglob("*")):
            if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
                continue
            contents = path.read_text(encoding="utf-8")
            if PRODUCTION_REFERENCE.search(contents):
                violations.append(str(path.relative_to(REPOSITORY_ROOT)))

        self.assertEqual(
            violations,
            [],
            "Prototype files must not become production integration surfaces.",
        )


if __name__ == "__main__":
    unittest.main()
