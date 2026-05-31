# /sync-check Skill

Layer-2 orchestrator that composes the SST3 wrapper-lane to surface code+doc+sync findings in one command. Wraps `dotfiles/scripts/sst3-check.sh`.

**Per Issue #445 Phase D** — single-command entry point to the wrapper-lane (Phases A + B + C).

## What this skill does

When invoked, this skill runs `bash dotfiles/scripts/sst3-check.sh` in the current repo and reports findings as a structured table. By default it runs all three areas (code, doc, sync); pass an arg to narrow scope.

## Usage

```
/sync-check                  → run all checks (code + doc + sync)
/sync-check code             → run code-side wrappers only (status, large, untested-py)
/sync-check doc              → run doc-side wrappers only (lint, yaml, frontmatter, links)
/sync-check sync             → run sync-side wrappers only (related-code, tool-eviction)
```

**What `/sync-check` does NOT compose** (intentional — these need explicit args):

The 6 code-query wrappers (`sst3-code-{callers,callees,subclasses,search,impact,review}.sh`) require a target symbol, pattern, or base-branch argument. They are not orchestrator-composable; invoke them directly when needed:

```bash
bash dotfiles/scripts/sst3-code-callers.sh <symbol> <lang>
bash dotfiles/scripts/sst3-code-callees.sh <function> <lang>
bash dotfiles/scripts/sst3-code-callees.sh <Class.method> <lang>          # method scoped to class
bash dotfiles/scripts/sst3-code-callees.sh <Class> <lang> --class         # union of all class methods
bash dotfiles/scripts/sst3-code-subclasses.sh <ClassName> <lang>          # reverse-inheritance lookup (#445 R4)
bash dotfiles/scripts/sst3-code-search.sh <pattern> <lang> [--literal]
bash dotfiles/scripts/sst3-code-impact.sh <base-branch>
bash dotfiles/scripts/sst3-code-review.sh <base-branch>
bash dotfiles/scripts/sst3-sync-doc-to-code.sh <doc-file> [<lang>]
```

Same applies to `sst3-sync-tool-eviction.sh <evicted_token>` — the orchestrator composes it with a runtime-constructed displaced-MCP token; for any other eviction guard, invoke directly.

## Orchestrator output contract (#445 R4)

Each invocation of `sst3-check.sh` emits, in addition to per-phase findings:

- `{kind:"orchestrator-progress", phase, status:"started"}` per phase
- `{kind:"orchestrator-progress", phase, status, findings, seconds, exit}` on phase completion
  - `status`: `complete | timeout | engine-missing | skipped | error`
- One terminating `{kind:"orchestrator-complete", mode, phases:[...], findings:N}` via EXIT trap (fires on SIGTERM / `set -e` / clean exit)

The terminator is the canonical "done" marker. Consumers that detect the orchestrator-complete sentinel can distinguish "all phases done" from "killed mid-stream" — silence is no longer ambiguous. Per-phase 90s timeout configurable via `$SST3_CHECK_PHASE_TIMEOUT`.

## What it composes

**Phase A — code wrappers**:
- `sst3-code-status.sh` — wrapper-lane status (last_updated, file_count)
- `sst3-code-large.sh 200 python` — functions over 200 lines

**Phase B — doc wrappers**:
- `sst3-doc-lint.sh` — markdownlint on SST3 / docs / CLAUDE.md / README.md
- `sst3-doc-yaml.sh` — yamllint on .github / .pre-commit-config.yaml / SST3 YAML
- `sst3-doc-frontmatter.sh` — frontmatter validity in docs/research/

**Phase C — sync wrappers**:
- `sst3-sync-related-code.sh` — frontmatter `related_code:` path drift detection
- `sst3-sync-tool-eviction.sh <displaced-mcp-token>` — eviction guard for the displaced MCP token (orchestrator constructs the token at runtime to avoid tripping its own guard)

## Output

NDJSON to stdout, one finding per line, each tagged with `kind: "<area>"`. Pipe to `jq` for filtering:

```bash
bash dotfiles/scripts/sst3-check.sh --all 2>/dev/null | jq -c 'select(.kind | startswith("doc-"))'
```

## Exit codes

- 0 — no findings
- 1 — findings emitted (review and fix)
- 127 — required inner engine missing (see `docs/guides/code-query-playbook.md` "Wrapper-Script Lane > Install")

## Required engines

Per the wrapper-lane install steps:
- `ast-grep` (cargo install ast-grep --locked)
- `ripgrep` (apt install ripgrep)
- `lychee` (cargo install lychee --locked)
- `markdownlint-cli2` (npm install -g markdownlint-cli2)
- `yamllint` (pipx install yamllint)
- `coverage` (pipx install coverage) — for code-untested-py
- `jq` (apt install jq)

If any engine is missing, the relevant wrapper exits 127 with a documented stderr contract message; `sst3-check.sh` continues with the rest.

## Pre-commit hook integration

`sst3-check.sh` is wired into pre-commit as the `sst3-check-orchestrator` hook (Phase D wiring per Issue #445).

## See also

- `docs/guides/code-query-playbook.md` — operational guide for the wrapper-lane
- `standards/wrapper-lane-tools.txt` — authoritative allow-list
- Issue #445 — the migration that introduced this lane
