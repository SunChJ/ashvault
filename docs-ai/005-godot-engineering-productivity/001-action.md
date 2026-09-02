# 005 — Godot Engineering Productivity: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-02 | Established the project engineering-productivity policy and agent rules. | Pending |

## Outcome & current state (as of 2026-09-02)

- `docs/GODOT_ENGINEERING_PRINCIPLES.md` is the maintained policy for
  reproducibility, time-to-test, native primitives, explicit dependencies,
  communication boundaries, content schemas, observability, save/reporting
  boundaries, and tooling ROI.
- `AGENTS.md` contains the eight short high-priority rules and concrete agent
  constraints. It links to the maintained policy instead of duplicating every
  rationale.
- The component-first rule remains intact for non-trivial solved subsystems.
  Small local code remains preferable when a dependency would weaken
  determinism or cost more than it saves.
- `docs/DEVELOPMENT_TASKBOOK.md` requires the shortest deterministic
  reproduction path and inspectable evidence for future tasks.
- The GitHub task template prompts for focused reproduction, observable output,
  and the full regression gate.
- No new tool, framework, plugin, runtime dependency, or product abstraction
  was introduced.

## Validation

- `git diff --check`
- Parsed `.github/ISSUE_TEMPLATE/task.yml` with `yaml.safe_load`.
- Ran 23 architecture, contract-freeze, CI-runner, and workflow unit tests; all
  passed.
- Reviewed repository-relative links against existing files.

## Deviations from plan

None. Bootstrap, run, build, export, Fast Start, Test Arena, domain debugger,
and Sentry implementation remain intentionally deferred until a product
workflow and observed friction justify their maintenance cost.

## Open questions

- Measure the first assembled combat loop before deciding whether Fast Start or
  a dedicated Test Arena is the smaller high-ROI intervention.
- Reassess local Godot acquisition only after fresh-clone setup becomes a
  repeated contributor or agent bottleneck.
