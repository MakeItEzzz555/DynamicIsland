# Fresh critical audit instructions

> Prepared 2026-09-19. Verified checkout: `df2bd0c29d06e8a01ec974459a118b232c8e22bc`, branch `phase-13c1-correctness-hotfix`. Local `origin/main` is `fbd1778ec025d9fa46d5f5f4f85c609b8375681b`; its Sources/, Tests/, Package.swift and Scripts/ match this HEAD. Only README differs (three removed lines). No checkout, pull or production edits were performed. `context.md` was already modified; historical evidence below includes that working-tree document. Source claims were checked in unchanged HEAD source. Recheck these summaries after implementation changes.

Preparation is complete; this file defines the next phase. Do not change source, tests, settings, packaging, docs, hooks or graph artifacts during the audit. Read-only graph queries may write Graphify query-cache metadata; treat that as tool bookkeeping, not authorized implementation work. Do not regenerate graph automatically during an audit; if stale, disclose the limitation and verify source directly.

## Start and evidence order

1. Read AGENTS.md and applicable nested guidance. Record git status, branch and full HEAD. Preserve all pre-existing changes. The baseline above describes preparation, not a mandate to checkout another branch or create another repository.
2. Query Graphify before broad source traversal (`graphify query`, `explain`, `path`, `affected`, `god-nodes`). Confirm outputs/freshness in graphify-out/. Current graph is code-only with limitations described in ARCHITECTURE_BASELINE.
3. Read graphify-out/GRAPH_REPORT.md for broad navigation, not as implementation truth.
4. Read all research/*.md, including architecture, invariants, incidents, known risks and this brief.
5. Consult context.md selectively using referenced phase headings for design rationale and regression constraints. It contains obsolete implementations and unperformed manual validation; distinguish historical reports from verified current facts.
6. Verify every finding against actual source at current HEAD. Check whether inspected working-tree source differs from HEAD; if it does, use git show HEAD:path for audit truth and identify the difference. Record exact files/functions/lines, upstream callers and relevant guards/tests.
7. Perform a complete, critical read-only application audit and produce a prioritized review first. Do not fix anything. Do not start a dev server, launch app or package merely to prepare evidence; run additional checks only when needed and explain their scope/side effects.

## Scope

Cover correctness, crashes and unsafe assumptions; concurrency and actor isolation; main-thread blocking, races and stale async callbacks; lifecycle and resource/memory leaks; event-monitor conflicts and AppKit/SwiftUI boundaries; polling/performance; persistence integrity and privacy/security; media selection/control/artwork; Clipboard extraction/copy-back/presentation; panels/Spaces/geometry/hit testing; accessibility; obsolete/dead code; architectural coupling/file complexity; documentation drift and meaningful missing tests.

Use graph queries scoped to native event routing, collapse ownership, Clipboard pasteboard-to-row flow, scroll pass-through, media provider-to-publish path, artwork raw-to-presented handoff, AppSettings readers/mutators, synchronous external work, and binary payload/persistence flows. A truncated graph query is not a complete absence/presence proof: narrow by actual symbol vocabulary, then inspect source.

## Finding format (required for each)

- **Severity:** Critical / High / Medium / Low
- **Confidence:** High / Medium / Low
- **Evidence:** current source behavior plus any reproduction/test evidence; distinguish inference.
- **Exact files/functions/lines:** clickable source references at audited HEAD.
- **Concrete failure scenario:** trigger, sequence and visible/system consequence.
- **Root cause:** causal mechanism, accounting for existing guards.
- **Recommended direction:** narrow fix recommendation; no implementation.
- **Regression risk:** relevant stable invariants and historical incidents.
- **Tests required:** meaningful deterministic tests and any unavoidable native/manual checks.

Prioritize impact and likelihood, not file size or graph degree. Do not rank speculative architectural preferences as bugs. Keep maintainability recommendations separate from demonstrated correctness defects; identify hypotheses requiring evidence and reject obsolete-history findings. Avoid restating the same root cause across multiple findings without explaining separate consequences.

## Validation and limits

Static review cannot certify real Spaces animation/input/accessibility behavior. State what was inspected, any tests actually run, what remains untested, and whether failure scenarios are reproduced or inferred. Do not report historical swift test/build results as newly passing. Retain the one-panel architecture, current timing values, coordinator generation guards and mounted Clipboard routing constraints in recommendations unless evidence justifies an explicit architecture change.

## Exact next prompt

> Read research/CRITICAL_AUDIT_BRIEF.md and follow it. Perform the fresh, complete architectural and correctness audit of DynamicIsland at current HEAD. Make no changes. Produce the prioritized review using the required finding format, verifying every important claim against current source and distinguishing confirmed defects, maintainability concerns and unverified hypotheses.
