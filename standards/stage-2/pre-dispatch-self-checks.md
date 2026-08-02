# Stage 2 — Pre-Dispatch Author Self-Check Block

> Cluster file loaded by `load-stage-rules.sh 2` (#516 AC 1.1 generalised loader).
> `.claude/commands/Leader.md` Stage 2 step 3.5 carries a concise pointer here. This is
> the MANDATORY author self-check the Leader runs on the `/tmp/issue_draft_<topic>.md`
> BEFORE dispatching any Layer-1/2 subagent (#516 AC 2.1). Zero unresolved items required
> before dispatch.

<!-- stages: 2 -->
## Sub-checks (a)–(t)

> Run ALL of (a)–(t). Items (j)–(t) are sub-sections of this catalogue below;
> they are not optional extras. (dotfiles#552 AC 4.5 — they were previously
> sibling `##` headings under a heading that said `(a)–(i)`, so an author who
> read the heading as the whole catalogue would skip them.)

- **(a) placeholder sweep** — `grep -E 'placeholder|stub|\bTODO\b|if needed|nice-to-have|could be|assumed|presumably|expected' /tmp/issue_draft_<topic>.md` → zero hits; re-run after every scope-reversal.
- **(b) scope-narrowing check** — every AC traces to the narrowed operator ask; an AC that does not map to the literal request is overreach — cut or justify.
- **(c) min-v1 sketch** — confirm a minimum-viable-v1 sketch is present BEFORE research-driven extensions; label extensions v1.1 / v2 with deferral rationale.
- **(d) template structure check** — `grep -nE '^### |^## ' $SST3/../templates/issue-template.md`; confirm each mandatory header is present in the draft. (dotfiles#552 AC 4.4: routed through the `$SST3` resolver instead of a bare literal path. `$SST3` ends at the scripts directory, so stepping up one level and into the sibling templates directory resolves in BOTH the nested canonical and the flattened mirror layout.)
- **(e) JBGE pass** — per-AC necessity check; delete any AC that does not prevent a real, named problem.
- **(f) budget sanity** — `wc -l` every target file before codifying any line-count budget; only codify a budget if planned additions are <30% of baseline, otherwise log the delta without a budget.
- **(g) reuse-before-new** — grep for any new script / subcommand / flag against existing entrypoints (AP #10 at draft-time); reuse in place if found.
- **(h) cross-repo state** — for every "existing X in repo Y" claim, `ls` / `grep` / `gh` against repo Y BEFORE writing the AC.
- **(i) multi-option AC classification** — mark each option as (i) evidence-supported → force, (ii) destructive-irreversible → operator-pre-consent, (iii) policy-level → defer.

<!-- stages: 2 -->
### Sub-check (j) — author-time source-read gate

- For every AC with a Before/After code block, run `Read` on the cited file:line and paste the ACTUAL code into the Before block.
- For every line-cited verbatim quote, run `sed -n '<line>p' <file>` and record the exit code + line number inline.
- For every AC naming a constant/symbol by file:line, re-grep at author-time (line numbers drift).
- For every count or literal-string verify predicate carried from Stage 1, re-execute the `grep` / `wc` at author-time — do not trust the Stage-1 number.
- For every "reuse existing X" claim, read X's full body + its transitive IO calls before asserting reuse is safe.
- **(#555 Phase 3)** When an AC pre-enumerates a command's expected output, RUN the command now and paste the ACTUAL output into the draft — never guess an output.
- **(#555 Phase 3)** For any file:line citation, `sed -n '<line>p' <file>` and confirm the cited line is the EXECUTABLE statement — not a comment or blank line — before writing the citation.
- **(#555 Phase 4)** For a reuse claim, read the target's actual signature — not an idealised shape — before writing the reuse clause.
- **(#555 Phase 4)** For a template/partial-include change, trace the FULL include chain to the owning template before drafting the Before/After.
- **(#555 Phase 4)** For a multi-file invariant AC, `Read` EVERY named file at its cited lines — not a representative one.
- **(#555 Phase 4)** For a re-sync AC, diff source vs target and enumerate exact per-occurrence replacement strings plus a verbatim-match verify — never a uniform 'replace all'.
- **(#555 Phase 4)** For a status-header/staleness claim, read the target's head and grep the EXACT stale string — never the paraphrase.

<!-- stages: 2 -->
### Shape-gated sub-check (k) — multi-root script file-availability

Fires when the draft touches a **bootstrap / installer / provisioning script that resolves files from more than one root** — a staged kit, a repo it clones part-way through its own run, or a hand-copied staging dir. Skip-clean otherwise.

- **(k) multi-root script file-availability** — for every AC that imports / sources / dot-sources a file inside such a script, identify WHICH root makes that file present **at that step's position in the run order**, before writing the import path. Check all of them in one pass — they are one question, not separate findings to surface across separate review rounds:
  - **pre-clone staged root** (`$PSScriptRoot`-style) — its LAYOUT varies by how the script was invoked: a flat-staged kit puts everything beside the script, while a run straight out of an existing clone keeps the repo's own `subdir\file` shape. Do not assume either; probe both shapes under this root,
  - **post-clone repo root** (only exists after the clone step — absent at every earlier step),
  - **operator-invoked staging dir** (the script was copied somewhere and run by hand; carries only a SUBSET of the kit, so "it's on the kit" is not sufficient).
- Establish the run-order position first — anchor the pattern to the script's own step-header form (`grep -nE '^# --- Step [0-9]'`-style), not a bare word match, which returns mostly prose cross-references. The same file can be reachable at one step and absent at an earlier one; the ordering is the whole check.
- Cite the in-file precedent: these scripts carry comments stating which root a given call must use and why. Read the precedent BEFORE choosing a root; do not infer from a nearby line that sits on the other side of the clone step.
- Prefer a guarded try-both (`Test-Path` / `[ -f ]`) over a single hardcoded path — both ACROSS roots when a call must work on either side of the clone step, and WITHIN the staged root when its layout depends on the invocation mode. Break on the first hit inside a probe loop, so one resolution wins.
- Where a LATER step can re-load the same file — a second attempt from a different root, whether or not the earlier one succeeded — guard that fallback on an already-loaded predicate — `Get-Command` / `command -v` / a sentinel variable — not on the earlier loop's break. A break only ends its own loop; it cannot stop a separate downstream block from re-sourcing the file and resetting whatever script-scope state the first load established.
- Repo-specific script names, manifest variables, and staging paths belong in the owning repo's own sweep issue — not in this catalogue (it mirrors to a public consumer).

<!-- stages: 2 -->
### Sub-check (l) — staged-benign-edit hook dogfood (#555 Phase 3)

- When the issue defers a secret-scan/leak-guard finding on a file the current AC set will ALSO touch, run the target repo's pre-commit hook on a staged benign edit to each AC-touched file at Stage 2. A whole-file block means the AC is commit-coupled to the deferred issue — sequence it after that issue or scope around it BEFORE implementation starts, not when Stage 4 hits the block.

<!-- stages: 2 -->
### Sub-check (m) — repo-gate preflight + baseline disposition (#555 Phase 3)

- For every in-scope file, pre-run the repo's OWN commit gates (voice-wrap, secret-scan) and pre-plan any exemption/allowlist remediation inside the AC body — a gate the repo will enforce at commit time is part of the AC's real acceptance surface.
- When an AC authors a whole-file gate globbing "all changed files", baseline-scan the REAL candidate set at Stage 2 so pre-existing violations in unrelated files get an explicit disposition before Stage 4 hits them as surprise blockers.
- **(#555 Phase 4)** For execution-path Issues, record which test tiers are environment-gated (conftest markers/skips) so Stage-4 sandbox-coverage is stated up front — not rediscovered at Gate 1.

<!-- stages: 2 -->
### Sub-check (n) — trace-to-endpoint (#555 Phase 3)

- For any "X produces Y" claim, read the call chain to the ACTUAL emitting statement before naming the fix locus — the most visible candidate is not proof; a plausible intermediate is not the producer.
- For any NEW payload field or code-level surface proposed as a decision gate, trace it to its user-visible consumer (frontend render / user-facing surface); if none exists, fold it into mechanism — it is not a scope choice.

<!-- stages: 2 -->
### Sub-check (o) — runtime-effect trace (#555 Phase 4)

- Before writing an AC about a longer string in a shared UI slot, check CSS wrap/overflow at the slot and add a wrap AC by default.
- Before marking a raise-site or side-write 'safe', `Read` the enclosing try/except and cite what it actually catches / rolls back — a non-critical side-write inside a transactional path needs the rollback logic cited, not assumed.
- Before computing from a nullable field, `Read` the nearest fail-fast guard and decide the compute-locus relative to it, citing its real file:line — never a placeholder.
- For any AC that sets/changes an HTTP status or response shape on an endpoint with a live UI consumer, include the writer→reader trace (grep frontend `resp.ok`/status branching) as a draft-time requirement — not a check deferred to Stage 5.

<!-- stages: 2 -->
### Sub-check (p) — shared-component consumer sweep (#555 Phase 4)

- When the topic touches a shared component / structure / UI marker, grep the component name and import path to enumerate EVERY mount site, consumer, and branch point, and carry the full list into the scope snippet BEFORE drafting per-site ACs (start the sweep at the Stage-1 SEED where possible). Distinct from AP #14e's pattern-class sibling sweep: this targets RUNTIME CONSUMERS of a shared component's presence, not spellings of a pattern.

<!-- stages: 2 -->
### Sub-check (q) — provisional live-probe tag (#555 Phase 4)

- Any AC whose rationale cites a live-DB-probe result (not re-derivable by grep against static source) is marked `[provisional: live-probe]` in the draft, with a mandatory Stage-3 re-probe of the SAME query recorded as a blocking sub-check before the scope freezes — live state can change between Stage 2 and Stage 3/4.

<!-- stages: 2 -->
### Sub-check (r) — drift-prone identifier live-verify pairing (#555 Phase 4)

- Whenever an AC enumerates platform/vendor identifiers a research finding flags as cosmetic/unstable (permission-group names, API fields), pair the enumeration with a verify-against-live clause in the SAME AC (a live API / permission-list call) — a static grep against the drafted list alone passes against a stale identifier set the vendor has since renamed.

<!-- stages: 2 -->
### Sub-check (s) — propagation-claim field-level verification (#555 Phase 4)

- Before asserting 'X propagates to mirror Y', read the vendored_files entry's `divergent` and transform-tier fields in `../dotfiles/SST3/drift-manifest.json` — if `divergent: true`, the propagation claim is FALSE and must be rewritten (the mirror is hand-authored, not round-tripped); list-presence alone is not propagation.

<!-- stages: 2 -->
### Sub-check (t) — early synthetic repro at filing time (#555 Phase 4)

- For wrapper-lane bug-fix topics, run the synthetic tmp-repo pre-fix repro BEFORE Stage-1 dispatch or during Stage-2 authoring (the same harness Stage 4 would use) and paste its pre-fix FAIL output into the issue body alongside any live-repo evidence — a false-positive bug claim caught here saves a full Stage-1/2/3 cycle.
