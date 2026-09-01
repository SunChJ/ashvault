from __future__ import annotations

import argparse
import os
import platform
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Optional, Sequence


PINNED_GODOT_VERSION = "4.7.2"


@dataclass(frozen=True)
class TestCommand:
    name: str
    arguments: list[str]


def resolve_godot(
    explicit: Optional[str],
    environment: Mapping[str, str] = os.environ,
    system: str = platform.system(),
    which: Callable[[str], Optional[str]] = shutil.which,
) -> Path:
    candidates: list[str] = []
    if explicit:
        candidates.append(explicit)
    elif environment.get("ASHVAULT_GODOT"):
        candidates.append(environment["ASHVAULT_GODOT"])
    else:
        discovered = which("godot") or which("godot4")
        if discovered:
            candidates.append(discovered)
        if system == "Darwin":
            candidates.append("/Applications/Godot.app/Contents/MacOS/Godot")

    if not candidates:
        raise FileNotFoundError(
            "Godot executable was not found. Pass --godot or set ASHVAULT_GODOT."
        )

    candidate = Path(candidates[0]).expanduser()
    if not candidate.is_file():
        raise FileNotFoundError(f"Godot executable does not exist: {candidate}")
    return candidate.resolve()


def validate_godot_version(
    godot: Path,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> None:
    completed = runner(
        [str(godot), "--version"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    output = completed.stdout.strip()
    if completed.returncode != 0:
        raise RuntimeError(
            f"Failed to query Godot version with exit code {completed.returncode}: {output}"
        )
    if not output.startswith(f"{PINNED_GODOT_VERSION}."):
        raise RuntimeError(
            f"Expected Godot {PINNED_GODOT_VERSION}, got: {output or '<empty>'}"
        )


def build_commands(godot: Path, repository_root: Path) -> list[TestCommand]:
    project_root = repository_root / "project-ashvault"
    performance_report = (
        repository_root / ".artifacts" / "performance" / "ci-baseline.json"
    )
    simulation_report = (
        repository_root / ".artifacts" / "simulation" / "ci-report.json"
    )
    godot_base = [str(godot), "--headless", "--path", str(project_root)]
    return [
        TestCommand(
            "python-tests",
            [
                sys.executable,
                "-m",
                "unittest",
                "tests/architecture/test_production_boundaries.py",
                "tests/architecture/test_m0_contract_freeze.py",
                "tests/tools/ci/test_run_tests.py",
                "tests/tools/ci/test_workflow_contract.py",
                "tests/tools/performance/test_validate_report.py",
                "tests/tools/simulation/test_run_headless.py",
                "tests/tools/simulation/test_validate_report.py",
                "tests/tools/research/test_sync_hero_siege.py",
            ],
        ),
        TestCommand(
            "m0-contract-freeze",
            godot_base
            + ["--script", "res://tests/production/test_m0_contract_freeze.gd"],
        ),
        TestCommand(
            "production-identity-contracts",
            godot_base
            + ["--script", "res://tests/production/test_identity_contracts.gd"],
        ),
        TestCommand(
            "production-content-catalog",
            godot_base
            + ["--script", "res://tests/production/test_content_catalog.gd"],
        ),
        TestCommand(
            "production-performance-metrics",
            godot_base
            + ["--script", "res://tests/production/test_performance_metrics.gd"],
        ),
        TestCommand(
            "production-rng-streams",
            godot_base + ["--script", "res://tests/production/test_rng_streams.gd"],
        ),
        TestCommand(
            "production-stats",
            godot_base + ["--script", "res://tests/production/test_stats.gd"],
        ),
        TestCommand(
            "production-damage-pipeline",
            godot_base
            + ["--script", "res://tests/production/test_damage_pipeline.gd"],
        ),
        TestCommand(
            "production-combat-events",
            godot_base
            + ["--script", "res://tests/production/test_combat_events.gd"],
        ),
        TestCommand(
            "production-abilities",
            godot_base
            + ["--script", "res://tests/production/test_abilities.gd"],
        ),
        TestCommand(
            "production-entity-commands",
            godot_base
            + ["--script", "res://tests/production/test_entity_commands.gd"],
        ),
        TestCommand(
            "production-headless-simulation",
            godot_base
            + ["--script", "res://tests/production/test_headless_simulation.gd"],
        ),
        TestCommand(
            "headless-simulation-cli",
            [
                sys.executable,
                "-m",
                "tools.simulation.run_headless",
                "--godot",
                str(godot),
                "--build",
                str(project_root / "tests/fixtures/headless_build.json"),
                "--encounter",
                str(project_root / "tests/fixtures/headless_encounter.json"),
                "--replay",
                str(project_root / "tests/fixtures/headless_replay.json"),
                "--root-seed",
                "424242",
                "--simulation-version",
                "1",
                "--content-version",
                "1",
                "--duration-seconds",
                "2",
                "--output",
                str(simulation_report),
            ],
        ),
        TestCommand(
            "simulation-report-schema",
            [
                sys.executable,
                "-m",
                "tools.simulation.validate_report",
                str(simulation_report),
            ],
        ),
        TestCommand(
            "performance-baseline",
            godot_base
            + [
                "--script",
                "res://tools/performance/run_baseline.gd",
                "--",
                "--output",
                str(performance_report),
            ],
        ),
        TestCommand(
            "performance-report-schema",
            [
                sys.executable,
                "-m",
                "tools.performance.validate_report",
                str(performance_report),
            ],
        ),
        TestCommand(
            "numerical-core",
            godot_base + ["--script", "res://tests/test_numerical_core.gd"],
        ),
        TestCommand(
            "numerical-sketch",
            godot_base + ["--script", "res://tests/test_numerical_sketch.gd"],
        ),
        TestCommand("main-scene-smoke", godot_base + ["--quit-after", "120"]),
    ]


def run_all(
    commands: Sequence[TestCommand],
    repository_root: Path,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> int:
    github_actions = os.environ.get("GITHUB_ACTIONS") == "true"
    for command in commands:
        if github_actions:
            print(f"::group::{command.name}", flush=True)
        print(f"$ {shlex.join(command.arguments)}", flush=True)
        completed = runner(
            command.arguments,
            cwd=repository_root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        output = completed.stdout or ""
        if output:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
        godot_output_error = "--headless" in command.arguments and any(
            line.lstrip().startswith(("ERROR:", "SCRIPT ERROR:"))
            for line in output.splitlines()
        )
        return_code = completed.returncode or (1 if godot_output_error else 0)
        if github_actions:
            print("::endgroup::", flush=True)
        if return_code != 0:
            if github_actions:
                print(
                    f"::error title={command.name} failed::Exit code {return_code}",
                    flush=True,
                )
            return return_code
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Ashvault validation suite.")
    parser.add_argument("--godot", help="Path to the pinned Godot executable.")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    repository_root = Path(__file__).resolve().parents[2]
    try:
        godot = resolve_godot(arguments.godot)
        validate_godot_version(godot)
    except (FileNotFoundError, RuntimeError) as error:
        print(f"Test runner setup failed: {error}", file=sys.stderr)
        return 2

    print(f"Using Godot {PINNED_GODOT_VERSION}: {godot}", flush=True)
    return run_all(build_commands(godot, repository_root), repository_root)


if __name__ == "__main__":
    raise SystemExit(main())
