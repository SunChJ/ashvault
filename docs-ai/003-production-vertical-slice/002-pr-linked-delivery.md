# 003.002 — PR-linked delivery

## Context

M0-01 through M0-03 were initially pushed directly to `main` and then closed by
CLI with verification comments. The commits were traceable, but the Issues had
no review surface or GitHub development linkage. That weakens change review and
makes Issue closure semantics inconsistent with the taskbook.

## Change

Every executable Issue now requires:

```text
Issue -> dedicated branch -> verified PR with `Closes #N` -> merge
```

Direct Issue closure is limited to administrative cancellation or supersession
and must state the reason. Direct pushes to `main` are not an implementation
delivery path.

M0-01 through M0-03 are reopened and receive separate corrective hardening PRs.
The historical commits remain intact; no empty PR, revert cycle, history rewrite,
or false chronology is introduced.

## Validation

- Each corrective PR contains a real change within the original Issue scope.
- Each PR body uses the matching closing keyword.
- GitHub automatically closes each Issue after merge.
- The taskbook records the delivery invariant.

## Current state

This policy applies to M0-01 and every subsequent executable Issue. Historical
direct commits remain linked from their Issue comments as implementation
evidence.
