# Stage 2 — Layer-1 / Layer-2 Draft-Check Prompt Angle Catalogue

> Cluster file loaded by `load-stage-rules.sh 2` (#516 AC 1.1 generalised loader).
> `.claude/commands/Leader.md` Stage 2 steps 5/6 carry a concise pointer here. Verbose
> catalogue of the angles the draft-check swarm runs against the `/tmp` issue draft
> (#516 AC 2.4). Layer-2 prompts MUST differ from Layer-1 (AP #14c).

<!-- stages: 2 -->
## Layer-1 draft-check angles (step 5)

- **scope-mapping** — every Stage-1 finding maps to a draft scope item (full coverage).
- **implementation-correctness** — for every AC, verify the verb-and-`file:line` against current source; flag any AC whose change description contradicts the actual source state.
- **carve-out respect** — for each Stage-1 Hard NO / deferred / follow-up carve-out, confirm the draft does not re-absorb it.

<!-- stages: 2 -->
## Layer-2 draft-check angles (step 6 — DIFFERENT prompt, AP #14c)

- **gaps / overengineering / false-positives** — the base Layer-2 mandate.
- **backwards-compatibility source-read** — read the EXISTING code at the relevant `file:line` BEFORE evaluating any backwards-compatibility, semantic-equivalence, or literal-accuracy claim.
- **marker-substring enumeration sweep** — for any YAML config an AC touches, enumerate stale documentation embedded in config values (comments inside config that describe the old shape).

<!-- stages: 2 -->
## Optional shape-gated Layer-2 angles (fire only on the matching shape)

- **admin-context PowerShell** — grep `HKCU` writes inside admin-context functions (admin context writes the wrong hive).
- **service-name literals in role-gate logic** — cross-reference each literal against the product's documented install output.
- **new concurrency primitive** — `git log -S '<primitive>'` before proposing the introduction of any new concurrency primitive (lock, queue, semaphore) — confirm one does not already exist.
