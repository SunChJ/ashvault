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
ROOT_REFERENCE = re.compile(
    r"(?:res://game/|(?:\.\./)+)(simulation|content|presentation|infrastructure)/"
)
GLOBAL_RANDOM_CALL = re.compile(
    r"(?<![.\w])(?:randf|randf_range|randfn|randi|randi_range|randomize|seed)\s*\("
)
RNG_WRAPPER = PRODUCTION_ROOT / "simulation/random/deterministic_rng_stream.gd"
ABILITY_EXECUTOR = PRODUCTION_ROOT / "simulation/abilities/ability_executor.gd"
SCENE_DRIVEN_SIMULATION = re.compile(r"^extends\s+(?:Node\w*|SceneTree)\s*$", re.MULTILINE)
FORBIDDEN_DEPENDENCIES = {
    "content": {"simulation", "presentation", "infrastructure"},
    "simulation": {"presentation", "infrastructure"},
    "presentation": {"infrastructure"},
    "infrastructure": set(),
}


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

    def test_production_root_dependencies_follow_ownership_direction(self) -> None:
        violations: list[str] = []
        for owner, forbidden_roots in FORBIDDEN_DEPENDENCIES.items():
            for path in sorted((PRODUCTION_ROOT / owner).rglob("*")):
                if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
                    continue
                contents = path.read_text(encoding="utf-8")
                referenced_roots = set(ROOT_REFERENCE.findall(contents))
                invalid_roots = sorted(referenced_roots & forbidden_roots)
                if invalid_roots:
                    relative_path = path.relative_to(REPOSITORY_ROOT)
                    violations.append(f"{relative_path}: {', '.join(invalid_roots)}")

        self.assertEqual(
            violations,
            [],
            "Production roots must follow the documented dependency direction.",
        )

    def test_randomness_is_owned_by_the_deterministic_stream_wrapper(self) -> None:
        violations: list[str] = []
        for path in sorted(PRODUCTION_ROOT.rglob("*.gd")):
            contents = path.read_text(encoding="utf-8")
            if GLOBAL_RANDOM_CALL.search(contents):
                violations.append(f"{path.relative_to(REPOSITORY_ROOT)}: global call")
            if path != RNG_WRAPPER and "RandomNumberGenerator" in contents:
                violations.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}: direct generator"
                )

        self.assertEqual(
            violations,
            [],
            "Production randomness must flow through deterministic named streams.",
        )

    def test_ability_execution_does_not_branch_on_item_ids(self) -> None:
        contents = ABILITY_EXECUTOR.read_text(encoding="utf-8")

        self.assertNotIn(
            "item.",
            contents,
            "Ability execution must consume transforms and modifiers, not item IDs.",
        )
        self.assertNotIn(
            "item_name",
            contents,
            "Ability execution must not branch on localized or authored item names.",
        )

    def test_simulation_is_not_scene_tree_driven(self) -> None:
        violations: list[str] = []
        for path in sorted((PRODUCTION_ROOT / "simulation").rglob("*.gd")):
            contents = path.read_text(encoding="utf-8")
            if SCENE_DRIVEN_SIMULATION.search(contents):
                violations.append(str(path.relative_to(REPOSITORY_ROOT)))

        self.assertEqual(
            violations,
            [],
            "Production simulation state must remain scene-independent.",
        )

    def test_simulation_has_no_scene_or_rendered_frame_dependency(self) -> None:
        forbidden_tokens = (
            "SceneTree",
            "get_tree(",
            ".tscn",
            "process_frame",
            "physics_frame",
        )
        violations: list[str] = []
        for path in sorted((PRODUCTION_ROOT / "simulation").rglob("*.gd")):
            contents = path.read_text(encoding="utf-8")
            observed = [token for token in forbidden_tokens if token in contents]
            if observed:
                relative_path = path.relative_to(REPOSITORY_ROOT)
                violations.append(f"{relative_path}: {', '.join(observed)}")

        self.assertEqual(
            violations,
            [],
            "Production simulation must not import gameplay scenes or frame lifecycle.",
        )


if __name__ == "__main__":
    unittest.main()
