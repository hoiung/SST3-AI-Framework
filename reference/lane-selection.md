# Wrapper-Lane vs Raw-Tool Selection (#447 Phase 5)

When to invoke `../scripts/sst3-code-*.sh` wrappers vs drop to
raw tools (grep / ast-grep direct / find / git log). Win-condition
heuristic distilled from the Issue #445 + #447 dogfood research.

## When to use the wrapper-lane

Default — wrapper-lane is the right call for these query classes:

- Structural code questions in a supported language (Python, TypeScript,
  TSX, JavaScript, Rust): callers, callees, subclasses, large
  functions, untested-py, blast-radius, dead-code candidates.
- Audit-trail metadata: file_count + last_updated for Stage 1 + Stage 5
  wrapper-lane status checkpoints.
- Cross-document drift: frontmatter validator, related_code path-drift,
  doc-to-code sync, link liveness.
- Composite Layer-2 audit: `sst3-check.sh --all` + `sst3-code-review.sh`.
- ANY case where the question + answer fits inside the wrapper's
  documented NDJSON schema and the engine is installed.

The wrapper-lane gives you: schema-stable NDJSON output, three-signal
contract enforcement, request-scoped statelessness (no cache to refresh),
and a self-test gate that catches regressions before ship.

## When to use raw tools

Drop to raw tools (grep / ast-grep direct / find / git log) for:

- **Engines unavailable** — wrapper exits 127. Use the raw fallback
  recipe in `../docs/guides/code-query-playbook.md` "Raw
  Fallback Recipes" table; record the substitution in your RESULT block.
- **Cross-validation moments** — the 4 cases enumerated in
  STANDARDS.md "Raw-tool cross-validation REQUIRED moments":
    1. Any change to wrapper-lane scripts.
    2. Any structural query producing zero results (silent-zero check).
    3. Post-implementation review of changes >100 LOC.
    4. Subagent RESULT block with `wrapper_invokable: yes` AND
       `wrapper_invoked: no` without documented reason.
- **Wrapper recall delta >20%** — when wrapper output diverges from raw
  output by more than 20%, treat the wrapper as SUSPECT and dispatch
  matched wrapper+raw subagent pairs for layer 1; reconcile in the
  research file.
- **Unsupported languages** (md/yaml/json/sql/toml/sh outside the 5
  ast-grep-wired langs, except where the wrapper has explicit non-AST
  branches like `sst3-code-large.sh` markdown heading-block heuristic).
- **Semantic / intent / cross-document / non-code work** — the 12
  subagent-only moments per AP #19 carve-out. Wrapper-lane is AST-only;
  it does not parse intent, voice, motivation, or cross-document drift.

## Validation experiment design

When designing a new wrapper or evaluating wrapper recall, the
pattern from #445 Stage 5 + #447 Phase 4 is:

1. **Pick a target repo** with a known sample (≥20 ground-truth instances
   of the symbol class — e.g. 52 oversized functions in
   auto_pb_swing_trader, 6 broken cv-linkedin doc links).
2. **Run the wrapper** + the raw equivalent in parallel against the same
   target. Capture both outputs.
3. **Compute recall** = wrapper-matched-instances / ground-truth-total.
   Compute precision = wrapper-matched / wrapper-emitted (ground-truth-of-emitted).
4. **Set the bar** — wrappers must match raw on the structural angle
   (recall ≥95%, precision ≥95%) before they ship. The R4 wrappers post-
   #445 closed all bugs at 100% recall on their canonical fixtures.
5. **Record the experiment** in `../docs/research/wrapper-lane-vs-raw/03_comparison.md`
   so the next dogfood pass has a baseline to delta against.

The Phase 4 self-test gate enforces (4) at every commit + CI run; the
Phase 5 raw-tool cross-validation enforces (4) at runtime on every
load-bearing wrapper invocation.

## Effort calibration (research carry-forward)

For estimation: structural queries via wrapper-lane are typically
30-60s per call (cold cache, includes engine startup). Raw equivalents
are similar speed but require crafting the regex / AST pattern, which
adds 1-3 minutes of agent time. The wrapper-lane wins on agent-time
amortisation — you write the pattern ONCE in the wrapper, every future
call is one bash line.

When the agent-time-to-craft beats the wrapper coverage gap (e.g. for
one-off queries no wrapper covers), raw is correct. For repeated
queries against the same query class, write a wrapper.

## See also

- STANDARDS.md "Structural Code Queries" — pre-query gate + 12-moments
  carve-out.
- ANTI-PATTERNS.md AP #19 — subagent-only moments.
- `../docs/guides/code-query-playbook.md` — Raw Fallback
  Recipes + Three Failure Shapes.
- `../docs/research/wrapper-lane-vs-raw/03_comparison.md` —
  empirical recall comparison + 33-shape failure-mode taxonomy.
- `tool-selection-guide.md` — broader Decision Tree for code-understanding
  queries.
