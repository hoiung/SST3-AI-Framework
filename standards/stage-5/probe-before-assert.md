# Stage 5 — Probe-before-Assert (AP #29 worked examples + probe recipes)

> Cluster file loaded by `load-stage-rules.sh 5`. Verbose worked-example catalogue for
> ANTI-PATTERNS.md AP #29 "Probe-before-Assert". The canonical rule lives in ANTI-PATTERNS.md;
> this file holds the per-target probe recipes (Append-vs-Extend). dotfiles#516 AC 5.2.

## The rule

Before asserting a **contract, parameter mode, endpoint behaviour, file absence, or tool
availability** — run a live probe command and capture its output inline. Treat absence as an
*unverified hypothesis*: a `grep` returning nothing proves your grep, not the world. "X is done /
deployed / met" at Stage 5 is a claim about live state — verify it by reading the live state (ledger
row, log line, DB value, CI conclusion), not by re-reading the diff that was *supposed* to produce it.

## Per-target probe recipes

### Endpoint behaviour / existence
Use a **non-side-effecting** verb to probe a route — NEVER a live `POST` against a side-effecting
endpoint (a probe must not mutate the system it is probing):
- `curl -sS -X OPTIONS <url>` (allowed methods) or `curl -sS --head <url>` (existence + headers).
- `curl -sS <base>/openapi.json | jq '.paths | keys'` (route inventory from the spec).
- Confirm the param mode (read-only vs read-write, required vs optional) from the OpenAPI schema or a
  GET probe before writing code that assumes it. (Provenance: an accidental ~50-min backfill fired from
  a `POST` used as an existence check.)

### File / symbol / config absence
- `ls <path>` / `test -f <path>` before asserting a file "doesn't exist".
- Synonym-swept `grep -rn` (multiple spellings) before "no match" — a single narrow pattern proves only
  that spelling is absent (cross-ref AP #14e concept-based grep).
- For "tool not installed": run the tool's `--version` (exit 127 = genuinely missing on disk) rather
  than assuming from a stale PATH or memory.

### Deploy / "the goal is met" (Stage 5 production-state)
- Read the **live ledger/log/DB row** that the change was supposed to write — not the diff. "Code
  written" is not "problem solved"; the Stage 5 production-state L1 angle reads live state post-deploy.
- Split a `git pull` from a `systemctl restart` into separate steps — an interrupt cannot undo a
  `SIGTERM` once dispatched, so verify the pull landed before restarting.
- Pre-flight the repo's CI before dispatching the Stage-5 swarm: `gh run list --limit 5 --json conclusion`
  — surface any FAILURE first (a red pipeline invalidates "the change is green").

### Tool / contract availability inside a swarm
- A subagent asserting "the graph/wrapper is unavailable" must show the probe (`wrapper --version`,
  exit code, stderr) — `mcp_graph_available: no` + evidence is a PASS; `no` + no-evidence is a FAIL.

## Why absence is the dangerous case

The recurring failure is asymmetric: a *positive* assertion ("the endpoint accepts POST") usually gets
exercised and fails loudly if wrong, but a *negative* assertion ("that file doesn't exist", "no other
caller reads this key", "the deploy succeeded") is self-confirming — the cheap check that produced it
(one grep, one glance at the diff) is exactly the check that misses the counter-example. Probe the
world, not your own query. Companion: AP #28 (source-of-intent — probe the source before consolidating);
AP #14c (verify against source, not subagent memory).
