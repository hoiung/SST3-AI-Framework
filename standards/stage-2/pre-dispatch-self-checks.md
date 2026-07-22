# Stage 2 — Pre-Dispatch Author Self-Check Block

> Cluster file loaded by `load-stage-rules.sh 2` (#516 AC 1.1 generalised loader).
> `.claude/commands/Leader.md` Stage 2 step 3.5 carries a concise pointer here. This is
> the MANDATORY author self-check the Leader runs on the `/tmp/issue_draft_<topic>.md`
> BEFORE dispatching any Layer-1/2 subagent (#516 AC 2.1). Zero unresolved items required
> before dispatch.

## Sub-checks (a)–(k)

> Run ALL of (a)–(k). Items (j) and (k) are sub-sections of this catalogue below;
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

### Sub-check (j) — author-time source-read gate

- For every AC with a Before/After code block, run `Read` on the cited file:line and paste the ACTUAL code into the Before block.
- For every line-cited verbatim quote, run `sed -n '<line>p' <file>` and record the exit code + line number inline.
- For every AC naming a constant/symbol by file:line, re-grep at author-time (line numbers drift).
- For every count or literal-string verify predicate carried from Stage 1, re-execute the `grep` / `wc` at author-time — do not trust the Stage-1 number.
- For every "reuse existing X" claim, read X's full body + its transitive IO calls before asserting reuse is safe.

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
