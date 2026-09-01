from __future__ import annotations

import argparse
import subprocess
from pathlib import Path
from typing import Sequence

from tools.ci.run_tests import resolve_godot, validate_godot_version


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROJECT_ROOT = REPOSITORY_ROOT / "project-ashvault"
SCRIPT_PATH = "res://tools/simulation/run_headless.gd"


def build_godot_command(godot: Path, arguments: argparse.Namespace) -> list[str]:
    return [
        str(godot),
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        "--script",
        SCRIPT_PATH,
        "--",
        "--build",
        str(arguments.build.resolve()),
        "--encounter",
        str(arguments.encounter.resolve()),
        "--replay",
        str(arguments.replay.resolve()),
        "--root-seed",
        str(arguments.root_seed),
        "--simulation-version",
        str(arguments.simulation_version),
        "--content-version",
        str(arguments.content_version),
        "--duration-seconds",
        str(arguments.duration_seconds),
        "--output",
        str(arguments.output.resolve()),
    ]


def parse_arguments(values: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Ashvault headless combat simulator.")
    parser.add_argument("--godot")
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--encounter", type=Path, required=True)
    parser.add_argument("--replay", type=Path, required=True)
    parser.add_argument("--root-seed", type=int, required=True)
    parser.add_argument("--simulation-version", type=int, required=True)
    parser.add_argument("--content-version", type=int, required=True)
    parser.add_argument("--duration-seconds", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args(values)
    for name in ("build", "encounter", "replay"):
        path: Path = getattr(arguments, name)
        if not path.is_file():
            parser.error(f"--{name} file does not exist: {path}")
    if not -(2**63) <= arguments.root_seed < 2**63:
        parser.error("--root-seed must fit a signed 64-bit integer")
    if arguments.simulation_version <= 0 or arguments.content_version <= 0:
        parser.error("versions must be positive")
    if arguments.duration_seconds <= 0:
        parser.error("--duration-seconds must be positive")
    return arguments


def main(values: Sequence[str] | None = None) -> int:
    arguments = parse_arguments(values)
    godot = resolve_godot(arguments.godot)
    validate_godot_version(godot)
    completed = subprocess.run(
        build_godot_command(godot, arguments),
        cwd=REPOSITORY_ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    output = completed.stdout or ""
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
    has_godot_error = any(
        line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:"))
        for line in output.splitlines()
    )
    return completed.returncode or (1 if has_godot_error else 0)


if __name__ == "__main__":
    raise SystemExit(main())
