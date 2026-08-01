<!-- stages: 4 -->
# Ralph Review — Stage-4 Canonical (#498 AC 4.1)

Three-tier code-delivery verification: Haiku surface → Sonnet logic → Opus deep. Sequential (not parallel); restart from Tier 1 on any tier FAIL. Runs INSIDE Stage 4 implementation BEFORE the Verification Loop's Gate 1.

## Tier sequence

| Tier | Model | Lens | Canonical checklist |
|------|-------|------|---------------------|
| 1    | `haiku`  | Surface — convention adherence, formatting, no-debug-leftovers | `../../ralph/haiku-review.md` |
| 2    | `sonnet` | Logic — control flow, edge cases, contract adherence, test seam | `../../ralph/sonnet-review.md` |
| 3    | `opus`   | Deep — architecture, cross-cutting, governance drift, wrapper-vs-raw counter-query | `../../ralph/opus-review.md` |

## Shared blocks (#498 Cut #10)

The three checklists `_*.md` shared blocks live in `../../ralph/`:
- `_wrapper-lane-preconditions.md` — wrapper-lane invocability + AP #19 `mcp_graph_available` rule.
- `_bash-output-discipline.md` — `tee-run.sh` wrap checkbox (#406 F4.9).
- `_doc-only-exemption.md` — doc-only PR exemption + #484 W6.3 doc-lane / sync-lane diff-trigger exceptions.
- `_fallback-clause.md` — retry-aware, evidence-required fallback clause.

## On FAIL

Fix → restart from Tier 1 (NOT continue from failed tier). Tier dependencies cascade: a Sonnet fix can re-break a Haiku check (e.g. introducing debug code) so the cheapest way to confirm clean is full re-run.

## On PASS (all 3)

Proceed to Verification Loop (Gate 1). Ralph PASS verifies code DELIVERY against the Issue's Acceptance Criteria; it does NOT substitute for Stage 5 adversarial audit (TB-3 N36 — different lens, different class of findings).

## Tier 3 wrapper-vs-raw counter-query (#447 Phase 5)

When ANY Tier-3 finding depends on `sst3-code-*.sh` wrapper output, Opus MUST dispatch ≥1 raw-tool counter-query subagent on the same target before signing PASS. Recall delta + reconciliation recorded inline in the Tier-3 review comment. Skipping when wrapper output is load-bearing = Tier-3 FAIL.

## Cross-references

- `.claude/commands/Leader.md` Stage 4 step 7 — the operator-facing Ralph trigger.
- `../../ralph/{haiku,sonnet,opus}-review.md` — per-tier canonical checklists.
- `../docs/research/model-selection-haiku-4-5.md` — model-selection rationale.

## Restart bound and escalation cycle

A Ralph ROUND is one dispatch of the tier sequence starting at Tier 1. A RESTART is a return to Tier 1 after a FAIL, so round N+1 begins with restart N.
The bound counts RESTARTS, not rounds.

Restarts 1 to 5: on any tier FAIL, fix and restart from Tier 1.
At the moment you restart, signal the counter: `bash ~/.claude/hooks/sst3-ralph-restart-counter.sh --restart`. This is REQUIRED, not optional bookkeeping. The SubagentStop event stream cannot see a restart at all — every tier dispatches under the same agent type, so a restart and an ordinary tier event are indistinguishable in it. The counter therefore derives NOTHING from event volume: unsignalled, the count stays 0 no matter how many events arrive, and the bound is never observed to be reached. (This paragraph previously said the stream "under-reports by up to 5x", which described an event-inference model that was removed — there is no partial credit, only 0.)

At fix time, on every restart: if a finding shares a root mechanism with an earlier finding in this issue, sweep the whole class before fixing.
Fix by the widest correct generalisation the evidence supports, not by the observed symptom. Guard-by-symptom fixing is what serialises one class member per restart.

Only a finding that changes SHIPPED BEHAVIOUR restarts the sequence. A finding confined to tests, comments, or documentation is recorded and fixed, but does not restart from Tier 1.
A finding that invalidates the EVIDENCE for an acceptance criterion counts as shipped behaviour and DOES restart. A vacuous test, a gate that passes without checking, and a surviving mutant are all evidence-invalidating.

Restart 6 is NOT taken. Escalate instead: run ONE class-sweep Workflow, then resume Ralph with the restart count reset to zero.
Effect that reset with `bash ~/.claude/hooks/sst3-ralph-restart-counter.sh --escalate`, which is the ONLY thing that resets the count. The counter is deliberately blind to the sweep's own subagents, so it cannot detect the escalation for itself; unsignalled, the count keeps climbing to 6, 7, 8 while this rule says 1 to 5 - wrong from cycle 2 onward, in exactly the repeating-cycle shape this bound exists to support.
The escalation Workflow carries no agent-count bound - size it to the angles - and MUST record its agent count and token cost.
Each escalation MUST use a different method from the previous escalation in this issue, and MUST record which method it used.
Its prompt shape is hunt and adversarial refute: parallel hunt angles enumerate the whole class in one pass, adversarial refuters try to find a survivor, and closure is declared only on an empty survivor set. Every new guard is mutation-verified.

The cycle repeats: up to 5 restarts, escalate, up to 5 restarts, escalate. Autonomy is never surrendered and there is no stop-and-ask terminal state.

The counter observes; the main agent enforces. No hook can redirect a dispatch.
