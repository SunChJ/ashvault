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
                "production-identity-contracts",
                "numerical-core",
                "numerical-sketch",
                "main-scene-smoke",
            ],
        )
        for command in commands[1:]:
            self.assertIn(str(repository_root / "project-ashvault"), command.arguments)

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
