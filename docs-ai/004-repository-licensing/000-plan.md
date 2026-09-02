# 004 — Repository Licensing: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-02 |
| **Primary refs** | [`LICENSE`](../../LICENSE), [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) |

## Background

The public repository has no declared license. Public visibility alone does not
provide a clear permission boundary, while the project owner requires that
commercial use not be granted.

## Decision

Apply the unmodified PolyForm Noncommercial License 1.0.0 to Ashvault-authored
material, with a project copyright required notice. State the commercial-use
boundary in the project README and keep third-party components under their own
upstream licenses.

PolyForm Noncommercial is source-available rather than an OSI-approved
open-source license. That distinction is intentional: noncommercial study,
modification, and redistribution are permitted, while commercial use is not.

## Alternatives

| Alternative | Decision |
| --- | --- |
| No license | Rejected: it leaves all reuse dependent on implicit copyright assumptions and does not communicate project intent. |
| MIT / Apache-2.0 | Rejected: both permit commercial use. |
| Creative Commons BY-NC | Rejected for project software: Creative Commons recommends against using its licenses for software. |
| Custom noncommercial terms | Rejected: custom wording creates avoidable interpretation and maintenance risk. |

## Scope

- Project-authored code, assets, content, and documentation are covered.
- Third-party plugins and assets retain their upstream terms.
- External research material and third-party intellectual property are not
  relicensed by this repository.

## Validation

- Keep the canonical PolyForm terms unchanged except for the permitted
  `Required Notice:` line.
- Place the license at the repository root for GitHub discovery.
- Preserve every bundled component license and maintain a third-party notice.
- Verify that only licensing and documentation files enter the delivery commit.
