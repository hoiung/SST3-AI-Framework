# Stage 1 — Domain-Class & Situational Angle Catalogue

> Cluster file loaded by `load-stage-rules.sh 1` (#516 AC 1.1). `.claude/commands/Leader.md`
> Stage 1 Step 2 points here (Append-vs-Extend). Dispatch the angles that match the task's
> domain class — additive to the generic Layer-1 coverage, not a replacement.

<!-- stages: 1 -->
## Required domain-class angles (dispatch the ones that match the task)

1. **vendor-behaviour** — when the task depends on a third-party product/API behaviour,
   `WebFetch` the vendor's official docs and verify the exact feature identity against
   them; never infer vendor behaviour from memory or from a sibling product. 403-fallback (#555 Phase 4): if `WebFetch` against the vendor's official domain 403s, fall back to `WebSearch` — an official-domain result snippet is valid, citable vendor evidence (cite it with its URL); never report 'no fetch performed'.
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
9. **UI/frontend-completeness** (#555 Phase 3) — for UI-accuracy-across-variants topics,
   default in a live-DB per-entity probe as a Layer-1 angle (the cheapest disambiguator
   of blank/partial/correct render state). For any pre-swarm gate verifying a "page X is
   windowed" claim, enumerate ALL bounce-data hooks in that page file — not only the
   handover-cited one. For UI-marker features, ask the surface-coverage + persistence
   questions upfront in the scope snippet, never reactively via wireframe reaction.
10. **incident-investigation (#555 Phase 4)** — when a reported timestamp does not map to any
    code-derived schedule, add a live-state reconciliation sub-task naming the exact runtime
    artefacts Stage 4 will need. For incident triage involving per-ticker/TTL'd Redis series,
    snapshot the relevant keys to /tmp (one `redis-cli GET` per key) BEFORE dispatching any
    research swarm — evidence must survive cohort eviction during the swarm's runtime.
11. **DB-probe verdicts (#555 Phase 4)** — dispatch DB-verdict angles as standalone subagents
    whose explicit first instruction is: run the decisive query FIRST, never buried in
    context-gathering. For writer/run-attribution claims, query which (run_id, variant) pairs
    actually wrote the rows and check provenance-metadata coexistence against the claimed
    writer's transaction shape before asserting exclusivity. For new equality-scoping from an
    operator list, probe the DB's stored casing/whitespace normalization before accepting a
    byte-identical match.
12. **redundancy/proxy-metric framing (#555 Phase 4)** — when the operator asks whether X is
    redundant with or a proxy for Y, the decisive test is a within-Y-conditioned cut (holding
    Y constant, does X still carry independent signal) — dispatch it as the primary analytical
    angle, not a correlation-only check.
13. **CMS-config template consumer (#555 Phase 4)** — for sites with a CMS config file (e.g.
    Sveltia/Decap `config.yml`), treat it as a mandatory Stage-1 read alongside the layout
    files — it is a template consumer whose field definitions must stay in sync with layout
    changes.
14. **CI-log fetch fallback (#555 Phase 4)** — when `gh run view --log` / `--log-failed`
    returns empty, do not retry view variants — call the zip endpoint directly:
    `gh api repos/<owner>/<repo>/actions/runs/<id>/logs`.
15. **new-content-surface linkage + claim audit (#555 Phase 4)** — for a new content page under
    an existing section, audit the section HUB / repo INDEX / nav-landing body it should be
    linked from; for a feature with a separate onboarding/runbook doc, enumerate every doc
    describing the changed workflow as in-scope; for a new data-processor/retention behaviour,
    grep the legal pages for every claim it invalidates. Fires at Stage-1/2 draft time — and a
    Stage-3 'settled / fails-safe' claim never exempts Stage-5 re-testing.

<!-- stages: 1 -->
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
4. **enumerate-before-bounding** — do not set an acceptance threshold, ceiling, or cap
   before the candidate set has been enumerated: enumerate first, then bound. A number
   chosen before the set exists is a guess wearing a threshold's clothing, and every later
   decision inherits it as though it were measured. Issue #52 fixed a reuse ceiling at
   "2-3" before the candidate sweep ran, then found the real set already saturated it.
5. **credential-role binding (#555 Phase 4)** — when the operator names a NEW credential,
   account, or identity in the task description, add an explicit research question binding
   it to a role — automation-consumed vs operator-manual-use — before scoping any AC that
   touches it. Naming an entity is not assigning its function.
6. **PowerShell tree-wide parse check (#555 Phase 4, shape-gated)** — for audits of repos
   bearing PowerShell scripts, dispatch a tree-wide PARSE check as a separate Layer-1 angle
   (not diff-scoped) — pre-commit parse-checks scan only staged files, so dormant parse bugs
   in unchanged files stay latent. Stage-5 twin lives in the post-implementation procedure.
