# Stage 2 — Pre-Dispatch Author Self-Check Block

> Cluster file loaded by `load-stage-rules.sh 2` (#516 AC 1.1 generalised loader).
> `.claude/commands/Leader.md` Stage 2 step 3.5 carries a concise pointer here. This is
> the MANDATORY author self-check the Leader runs on the `/tmp/issue_draft_<topic>.md`
> BEFORE dispatching any Layer-1/2 subagent (#516 AC 2.1). Zero unresolved items required
> before dispatch. Each item is a falsifiable author-time gate, not a vibe-check.

## The nine sub-checks (a)–(i)

- **(a) placeholder sweep** — `grep -E 'placeholder|stub|\bTODO\b|if needed|nice-to-have|could be|assumed|presumably|expected' /tmp/issue_draft_<topic>.md` → zero hits; re-run after every scope-reversal.
- **(b) scope-narrowing check** — every AC traces to the narrowed operator ask; an AC that does not map to the literal request is overreach — cut or justify.
- **(c) min-v1 sketch** — confirm a minimum-viable-v1 sketch is present BEFORE research-driven extensions; label extensions v1.1 / v2 with deferral rationale.
- **(d) template structure check** — `grep -nE '^### |^## ' templates/issue-template.md`; confirm each mandatory header is present in the draft.
- **(e) JBGE pass** — per-AC necessity check; delete any AC that does not prevent a real, named problem.
- **(f) budget sanity** — `wc -l` every target file before codifying any line-count budget; only codify a budget if planned additions are <30% of baseline, otherwise log the delta without a budget.
- **(g) reuse-before-new** — grep for any new script / subcommand / flag against existing entrypoints (AP #10 at draft-time); reuse in place if found.
- **(h) cross-repo state** — for every "existing X in repo Y" claim, `ls` / `grep` / `gh` against repo Y BEFORE writing the AC.
- **(i) multi-option AC classification** — mark each option as (i) evidence-supported → force, (ii) destructive-irreversible → operator-pre-consent, (iii) policy-level → defer.

## Sub-check (j) — author-time source-read gate

- For every AC with a Before/After code block, run `Read` on the cited file:line and paste the ACTUAL code into the Before block.
- For every line-cited verbatim quote, run `sed -n '<line>p' <file>` and record the exit code + line number inline.
- For every AC naming a constant/symbol by file:line, re-grep at author-time (line numbers drift).
- For every count or literal-string verify predicate carried from Stage 1, re-execute the `grep` / `wc` at author-time — do not trust the Stage-1 number.
- For every "reuse existing X" claim, read X's full body + its transitive IO calls before asserting reuse is safe.
