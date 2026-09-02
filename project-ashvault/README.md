# Project Ashvault

Ashvault is an ARPG systems prototype. The current executable is a numerical
combat sketch for validating damage layers, progression cadence, skill
milestones, and high-density power spikes before production content begins.

## Play

Open `project.godot` in Godot 4.7.2, or run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path project-ashvault
```

- Move with WASD or arrow keys.
- Storm Bolt and Arc Nova cast automatically.
- Collect green XP shards.
- Choose level-up upgrades with 1, 2, or 3.
- Press R after defeat to restart.

## Numerical model

Damage resolves through explicit multiplicative stages:

```text
base = source * (1 + enhanced) + flat
final = base
	  * (1 + increased)
	  * product(more)
	  * critical
	  * resistance_multiplier
	  * (1 + conditional)
```

Raw haste passes through a saturating transform before reducing action
intervals. Experience uses piecewise growth with slope changes at levels 6 and
11. Skill ranks provide modest convex damage growth, while ranks 3 and 5 add a
projectile and chain behavior respectively.

The prototype is intentionally disposable outside its two pure numerical
modules. It contains no production item, save, content, or rendering APIs.

Production development is governed by the repository-level
[`DEVELOPMENT_TASKBOOK.md`](../docs/DEVELOPMENT_TASKBOOK.md) and
[`ARPG_KERNEL_SPEC.md`](../docs/ARPG_KERNEL_SPEC.md). Production code must not
import the prototype as a gameplay dependency.

Production source belongs under [`game/`](game/README.md), separated into
simulation, content, presentation, and infrastructure roots. The current main
scene intentionally remains the numerical prototype until the production
composition root is ready.

## Validation

Run the complete local suite with the pinned Godot version:

```bash
python3 tools/ci/run_tests.py
```

The same runner executes on Windows and macOS CI. Individual numerical checks
remain available for focused iteration:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path project-ashvault \
  --script res://tests/test_numerical_core.gd

/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path project-ashvault \
  --script res://tests/test_numerical_sketch.gd
```

The second command runs a seeded three-minute balance sample and checks
upgrade, Overdrive, boss, milestone, kill-cadence, and density bands.

The production kernel can also run as a deterministic combat replay without a
rendered scene. See
[`PERFORMANCE_BASELINES.md`](../docs/PERFORMANCE_BASELINES.md#production-combat-replay)
for the explicit fixture CLI and report contract.

## License

Ashvault-authored code, game content, assets, and documentation are available
under the [PolyForm Noncommercial License 1.0.0](../LICENSE). Commercial use is
not granted.

Third-party software, assets, trademarks, and research material retain their
own terms and are not relicensed by Ashvault. See
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
