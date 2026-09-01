from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from tools.ci import run_tests


class CiTestRunnerTests(unittest.TestCase):
    def test_explicit_godot_path_takes_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "godot"
            executable.touch()

            resolved = run_tests.resolve_godot(
                explicit=str(executable),
                environment={"ASHVAULT_GODOT": "/ignored/godot"},
                system="Darwin",
                which=lambda _: None,
            )

        self.assertEqual(resolved, executable.resolve())

    def test_missing_explicit_godot_path_is_an_error(self) -> None:
        with self.assertRaisesRegex(FileNotFoundError, "does not exist"):
            run_tests.resolve_godot(
                explicit="/definitely/missing/godot",
                environment={},
                system="Darwin",
                which=lambda _: None,
            )

    def test_commands_cover_python_production_and_prototype_checks(self) -> None:
        repository_root = Path("/repo")
        commands = run_tests.build_commands(Path("/godot"), repository_root)
        names = [command.name for command in commands]

        self.assertEqual(
            names,
            [
                "python-tests",
                "m0-contract-freeze",
                "production-identity-contracts",
                "production-content-catalog",
                "production-performance-metrics",
                "performance-baseline",
                "performance-report-schema",
                "numerical-core",
                "numerical-sketch",
                "main-scene-smoke",
            ],
        )
        self.assertIn(
            "tests/tools/ci/test_workflow_contract.py",
            commands[0].arguments,
        )
        self.assertIn(
            "tests/architecture/test_m0_contract_freeze.py",
            commands[0].arguments,
        )
        self.assertIn(
            "tests/tools/performance/test_validate_report.py",
            commands[0].arguments,
        )
        godot_commands = [
            command for command in commands if command.arguments[0] == "/godot"
        ]
        for command in godot_commands:
            self.assertIn(str(repository_root / "project-ashvault"), command.arguments)

        baseline = next(
            command for command in commands if command.name == "performance-baseline"
        )
        validator = next(
            command
            for command in commands
            if command.name == "performance-report-schema"
        )
        expected_report = str(
            repository_root / ".artifacts" / "performance" / "ci-baseline.json"
        )
        self.assertEqual(baseline.arguments[-1], expected_report)
        self.assertEqual(validator.arguments[-1], expected_report)

    def test_version_check_requires_the_pinned_release(self) -> None:
        successful_run = Mock(stdout="4.7.2.stable.official\n", returncode=0)
        runner = Mock(return_value=successful_run)
        run_tests.validate_godot_version(Path("/godot"), runner=runner)

        wrong_run = Mock(stdout="4.8.stable.official\n", returncode=0)
        with self.assertRaisesRegex(RuntimeError, "Expected Godot 4.7.2"):
            run_tests.validate_godot_version(
                Path("/godot"),
                runner=Mock(return_value=wrong_run),
            )


if __name__ == "__main__":
    unittest.main()
