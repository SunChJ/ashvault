from __future__ import annotations

import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

from tools.simulation.run_headless import PROJECT_ROOT, SCRIPT_PATH, build_godot_command, parse_arguments


class HeadlessSimulationCliTests(unittest.TestCase):
    def test_builds_explicit_headless_godot_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixtures = [root / name for name in ("build.json", "encounter.json", "replay.json")]
            for fixture in fixtures:
                fixture.touch()
            output = root / "report.json"
            arguments = parse_arguments([
                "--build", str(fixtures[0]),
                "--encounter", str(fixtures[1]),
                "--replay", str(fixtures[2]),
                "--root-seed", "42",
                "--simulation-version", "1",
                "--content-version", "1",
                "--duration-seconds", "2",
                "--output", str(output),
            ])
            command = build_godot_command(Path("/godot"), arguments)

        self.assertEqual(command[:6], ["/godot", "--headless", "--path", str(PROJECT_ROOT), "--script", SCRIPT_PATH])
        self.assertIn("--root-seed", command)
        self.assertIn("42", command)
        self.assertEqual(command[-2:], ["--output", str(output.resolve())])

    def test_rejects_missing_input_file(self) -> None:
        with redirect_stderr(StringIO()):
            with self.assertRaises(SystemExit):
                parse_arguments([
                    "--build", "/missing/build.json",
                    "--encounter", "/missing/encounter.json",
                    "--replay", "/missing/replay.json",
                    "--root-seed", "42",
                    "--simulation-version", "1",
                    "--content-version", "1",
                    "--duration-seconds", "2",
                    "--output", "/tmp/report.json",
                ])


if __name__ == "__main__":
    unittest.main()
