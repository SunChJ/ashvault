from __future__ import annotations

import unittest
from pathlib import Path

from tools.ci.run_tests import PINNED_GODOT_VERSION


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"


class WorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_workflow_uses_the_runner_version(self) -> None:
        self.assertIn(
            f'GODOT_VERSION: "{PINNED_GODOT_VERSION}"',
            self.workflow,
        )
        self.assertIn(
            "godotengine/godot-builds/releases/download/",
            self.workflow,
        )

    def test_workflow_covers_both_supported_platforms(self) -> None:
        self.assertIn("os: [macos-14, windows-2022]", self.workflow)
        self.assertIn("Godot_v${env:GODOT_VERSION}-stable_macos.universal.zip", self.workflow)
        self.assertIn("Godot_v${env:GODOT_VERSION}-stable_win64.exe.zip", self.workflow)

    def test_workflow_runs_for_review_and_mainline_changes(self) -> None:
        self.assertIn("push:", self.workflow)
        self.assertIn("pull_request:", self.workflow)
        self.assertIn("workflow_dispatch:", self.workflow)

    def test_workflow_uses_the_shared_validation_entrypoint(self) -> None:
        self.assertIn(
            "python tools/ci/run_tests.py --godot $env:ASHVAULT_GODOT",
            self.workflow,
        )
        self.assertIn("uses: actions/checkout@v7", self.workflow)
        self.assertIn("uses: actions/setup-python@v7", self.workflow)


if __name__ == "__main__":
    unittest.main()
