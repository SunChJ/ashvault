from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
KERNEL_SPEC = REPOSITORY_ROOT / "docs/ARPG_KERNEL_SPEC.md"
OWNERSHIP_SPEC = REPOSITORY_ROOT / "project-ashvault/game/README.md"


class M0ContractFreezeTests(unittest.TestCase):
    def test_kernel_spec_declares_the_m0_freeze(self) -> None:
        specification = KERNEL_SPEC.read_text(encoding="utf-8")

        self.assertIn("| **Status** | M0 contracts frozen |", specification)
        self.assertIn("| **Version** | 1.0 |", specification)
        self.assertIn("## M0 contract freeze", specification)

    def test_kernel_spec_distinguishes_future_contracts(self) -> None:
        specification = KERNEL_SPEC.read_text(encoding="utf-8")

        self.assertIn("Implemented and frozen in M0", specification)
        self.assertIn("Accepted for downstream implementation", specification)
        self.assertIn("Breaking changes", specification)

    def test_production_ownership_direction_is_explicit(self) -> None:
        ownership = OWNERSHIP_SPEC.read_text(encoding="utf-8")

        self.assertIn("| `content/` | `content/` |", ownership)
        self.assertIn(
            "| `simulation/` | `simulation/`, `content/` |",
            ownership,
        )
        self.assertIn(
            "| `presentation/` | `presentation/`, `simulation/`, `content/` |",
            ownership,
        )
        self.assertIn("| `infrastructure/` | All production roots |", ownership)


if __name__ == "__main__":
    unittest.main()
