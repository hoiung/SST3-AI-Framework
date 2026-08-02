# Stage 5 — Probe-before-Assert (AP #29 worked examples + probe recipes)

> Cluster file loaded by `load-stage-rules.sh 5`. Verbose worked-example catalogue for
> ANTI-PATTERNS.md AP #29 "Probe-before-Assert". The canonical rule lives in ANTI-PATTERNS.md;
> this file holds the per-target probe recipes (Append-vs-Extend). dotfiles#516 AC 5.2.

<!-- stages: 5 -->
## The rule

Before asserting a **contract, parameter mode, endpoint behaviour, file absence, or tool
availability** — run a live probe command and capture its output inline. Treat absence as an
*unverified hypothesis*: a `grep` returning nothing proves your grep, not the world. "X is done /
deployed / met" at Stage 5 is a claim about live state — verify it by reading the live state (ledger
row, log line, DB value, CI conclusion), not by re-reading the diff that was *supposed* to produce it.

<!-- stages: 5 -->
## Per-target probe recipes

<!-- stages: 5 -->
### Endpoint behaviour / existence
Use a **non-side-effecting** verb to probe a route — NEVER a live `POST` against a side-effecting
endpoint (a probe must not mutate the system it is probing):
- `curl -sS -X OPTIONS <url>` (allowed methods) or `curl -sS --head <url>` (existence + headers).
- `curl -sS <base>/openapi.json | jq '.paths | keys'` (route inventory from the spec).
- Confirm the param mode (read-only vs read-write, required vs optional) from the OpenAPI schema or a
  GET probe before writing code that assumes it. (Provenance: an accidental ~50-min backfill fired from
  a `POST` used as an existence check.)

<!-- stages: 5 -->
### File / symbol / config absence
- `ls <path>` / `test -f <path>` before asserting a file "doesn't exist".
- Synonym-swept `grep -rn` (multiple spellings) before "no match" — a single narrow pattern proves only
  that spelling is absent (cross-ref AP #14e concept-based grep).
- For "tool not installed": run the tool's `--version` (exit 127 = genuinely missing on disk) rather
  than assuming from a stale PATH or memory.

<!-- stages: 5 -->
### Deploy / "the goal is met" (Stage 5 production-state)
- Read the **live ledger/log/DB row** that the change was supposed to write — not the diff. "Code
  written" is not "problem solved"; the Stage 5 production-state L1 angle reads live state post-deploy.
- Split a `git pull` from a `systemctl restart` into separate steps — an interrupt cannot undo a
  `SIGTERM` once dispatched, so verify the pull landed before restarting.
- Pre-flight the repo's CI before dispatching the Stage-5 swarm: `gh run list --limit 5 --json conclusion`
  — surface any FAILURE first (a red pipeline invalidates "the change is green").

<!-- stages: 5 -->
### Row-count / row-existence (Postgres)
For "the table has N rows" / "no rows remain in the bad state" / "the data is gone" claims, the
planner statistics `pg_stat_user_tables.n_live_tup` and `pg_class.reltuples` are ESTIMATES — they
read 0 or stale on a bulk-loaded-without-`ANALYZE` table and drift between autovacuum runs, so they
are NEVER load-bearing for a row-existence or row-count assertion. Use an exact `COUNT(*)` (with the
`WHERE` predicate that defines the claim) and read its value:
- `psql -At -c "SELECT COUNT(*) FROM <table> WHERE <predicate>;"` — the authoritative count.
- A row-existence check can stop early: `SELECT EXISTS (SELECT 1 FROM <table> WHERE <predicate>);`.
- An estimate that "looks like zero" is not zero. (Provenance: a Stage-5 subagent concluded "442K
  rows gone, only 16K left" from `n_live_tup=0`; a main-agent `COUNT(*)` then read 1,032,756 — the
  universe was intact. dotfiles#528 AC 6.2.)

<!-- stages: 5 -->
### DB-timestamp write frame — tz / date-bucketing changes (#555 Phase 3)
- Before asserting how a timestamp column buckets, probe the WRITE frame, not just the read side:
  the column type (`\d <table>` — `timestamp` vs `timestamptz`), the server frame (`SHOW timezone;`),
  and the writer path (`grep -rn '<column>'` across the writer modules — `now()` vs `utcnow()` vs a
  client-supplied value). A bucketing claim built from the read side alone inherits whichever frame
  the writer actually used.

<!-- stages: 5 -->
### GHA / service recovery (#555 Phase 3)
- Author recovery probes from the live unit, never memory: `systemctl show -p ExecStart <unit>`
  shows what actually runs. VERIFY recovery by re-running a real runner job — a green
  `systemctl status` proves the daemon, not the pipeline.

<!-- stages: 5 -->
### Assembled SQL — clause concatenated onto a constant (#555 Phase 3)
- When a SQL clause is concatenated onto a constant/base query, run a live `EXPLAIN` of the
  ASSEMBLED statement — a window-fn/keyword grep of the fragments proves the fragments, not the
  plan the database actually executes.

<!-- stages: 5 -->
### Live external state at Stage-5 entry (#555 Phase 3)
- Re-curl (or re-fetch) any live external surface a worked example cites AT STAGE-5 ENTRY and grep
  every worked example against the fresh capture — external state moves between Stage 1 and
  Stage 5; a stale capture silently verifies yesterday's world.

<!-- stages: 5 -->
### Tool / contract availability inside a swarm
- A subagent asserting "the graph/wrapper is unavailable" must show the probe (`wrapper --version`,
  exit code, stderr) — `mcp_graph_available: no` + evidence is a PASS; `no` + no-evidence is a FAIL.

<!-- stages: 5 -->
## Why absence is the dangerous case

The recurring failure is asymmetric: a *positive* assertion ("the endpoint accepts POST") usually gets
exercised and fails loudly if wrong, but a *negative* assertion ("that file doesn't exist", "no other
caller reads this key", "the deploy succeeded") is self-confirming — the cheap check that produced it
(one grep, one glance at the diff) is exactly the check that misses the counter-example. Probe the
world, not your own query. Companion: AP #28 (source-of-intent — probe the source before consolidating);
AP #14c (verify against source, not subagent memory).
