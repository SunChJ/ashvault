from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT_ROOT = REPOSITORY_ROOT / "project-ashvault"
PRODUCTION_ROOT = PROJECT_ROOT / "game"
REQUIRED_ROOTS = (
    "simulation",
    "content",
    "presentation",
    "infrastructure",
)
SCANNED_SUFFIXES = {".cs", ".gd", ".gdshader", ".tres", ".tscn"}
PROTOTYPE_REFERENCE = re.compile(r"(?:res://|(?:\.\./)+)prototype/")


class ProductionBoundaryTests(unittest.TestCase):
    def test_required_production_roots_exist(self) -> None:
        for root_name in REQUIRED_ROOTS:
            with self.subTest(root=root_name):
                self.assertTrue(
                    (PRODUCTION_ROOT / root_name).is_dir(),
                    f"Missing production root: game/{root_name}",
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


if __name__ == "__main__":
    unittest.main()
