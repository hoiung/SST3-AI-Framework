# Stage 1 — Domain-Class & Situational Angle Catalogue

> Cluster file loaded by `load-stage-rules.sh 1` (#516 AC 1.1 generalised loader).
> Verbose catalogue of named Stage-1 research angles. `.claude/commands/Leader.md`
> Stage 1 Step 2 carries a one-line pointer here (Append-vs-Extend; the canon stays
> concise, the catalogue lives here). Dispatch the angles that apply to the task's
> domain class; they are additive to the generic Layer-1 coverage, not a replacement.

## Required domain-class angles (dispatch the ones that match the task)

1. **vendor-behaviour** — when the task depends on a third-party product/API behaviour,
   `WebFetch` the vendor's official docs and verify the exact feature identity against
   them; never infer vendor behaviour from memory or from a sibling product.
2. **legal-multi-stack** — for any legal/compliance framing, run an Angle-0 sweep of the
   *non-data-protection* legal stack (company law, consumer law, contract, IP, sector
   regulation) before narrowing to the obvious statute; the obvious one is rarely the
   only one in force.
3. **GDPR** — when personal data is in scope, walk every data-subject right in GDPR
   Articles 12–23 individually and confirm the design satisfies (or explicitly defers)
   each; do not stop at "we have a privacy policy".
4. **post-system-change** — after any system/config change, grep the adjacent calibration
   surface (thresholds, defaults, dependent configs, downstream consumers) and enumerate
   every surface the change could have silently shifted.
5. **pipeline-architecture** — for pipeline/orchestration changes, dispatch a
   downstream-docs-staleness angle: walk CLAUDE.md / README / runbook references to the
   changing surface and flag any that now describe the old shape.
6. **business-workflow** — for business-ops/product work, include a design-system / brand
   angle so the deliverable matches the established voice, layout, and brand constraints,
   not just the functional spec.
7. **extending-prior-features** — when extending an existing feature v(N)→v(N+1), dispatch
   a schema-bridge angle: enumerate every persisted/serialised shape the prior version
   wrote and confirm the new version reads it (or migrates it) — no silent shape breaks.
8. **external-API** — for any external-API integration, dispatch a fallback-design-path
   angle: what happens on timeout / rate-limit / 5xx / auth-expiry, and is the fallback
   itself observable (not a silent swallow)?

## Situational angles (dispatch when the trigger condition holds)

1. **carve-out bullet-proofing** — when the operator flags a do-not-touch surface, dispatch
   an angle whose sole job is to confirm no AC re-absorbs or mutates that surface; the
   carve-out must hold against the *implementation*, not just the stated intent.
2. **dual-mode codepath split** — for tools with two execution modes (CLI + module / strict
   + lax / emit + validate), dispatch an angle that verifies BOTH codepaths are exercised
   and that a fix to one is mirrored to the other.
3. **synthesis ordering** — dispatch synthesis subagents AFTER confirmed task-completion
   notification of the inputs they read; never in parallel with the producers and never on
   a fixed timer (the inputs may not exist yet). The synthesis prompt names its input files.
