# Changelog

Notable changes to the SST3-AI-Harness public mirror.

The format follows the spirit of [Keep a Changelog](https://keepachangelog.com/);
each entry references the canonical-side Issue number where the change
originated.

## 2026-06-08 — Mirror sync: missing scripts + completeness gate + adopter docs (#523)

Brings the mirror current with the latest canonical SST3 and fixes the gate that
let scripts go undeclared.

### Newly mirrored framework scripts

- Mirrored 9 framework scripts the docs/hooks referenced but were absent:
  `check-ap22-cross-repo-cd.sh`, `check-phase-ac-cadence.py`,
  `check-stage1-research-fields.py`, `sst3-privacy-scan-issue-body.py`,
  `load-stage-rules.sh`, `setup-worktree-deps.sh`, `check-ai-writing-tells.py`,
  `voice_rules.py`, plus `extract-chat-agreements.py` (the verifier-led
  chat-reconciliation tool, hand-scrubbed as a divergent entry).
- This resolves the previously-dangling `sst3-issue-body-privacy-gate.sh` hook
  dependency (its `sst3-privacy-scan-issue-body.py` now ships here).

### De-referenced operator-only tooling

- Operator-only scripts (the propagation pipeline, per-stage-feedback tooling,
  `install.sh`, migration/rollout one-offs) now read as operator-side
  (`<your-dotfiles-clone>/…`) rather than as broken mirror-local paths — fixed at
  the transform layer so canonical stays clean. New `MIRROR-CONTRACT.md` note
  explains the `<your-dotfiles-clone>/` placeholder.

### Completeness gate hardened

- `check-manifest-completeness.sh` now enumerates `*.sh` (not just `*.md|*.py`)
  and requires every `SST3/scripts/*` to be explicitly declared — the blanket
  `SST3/` prefix no longer auto-classifies them (the false-clean bug). New
  `tests/SST3/test_manifest_completeness_gate.py` asserts it fails what it guards.

### Adopter docs refreshed

- README counts corrected (stage-4 extracts 9→12, ralph 6→10, scripts 73→82,
  self-test fixtures 32→30, statusline 343→342, `/Leader 1-6`→`1-5`, framework
  files →272); branch-safety now describes the worktree-isolation model; added
  Slash Commands (`/handover`, `/sync-check`) + Recent Capabilities (drain gate
  D1-D6, completeness gate, chat reconciliation, Workflow-tool default engine).

## 2026-05-24 — Public mirror sync hardening (#501)

Brings the public mirror into a clean post-revamp state. Closes 13 distinct
findings F1–F13 across 4 phases:

### Privacy hardening

- The private term mapping table (10 private consumer-repo names + 40
  operator-identity substitution pairs + 2 word-bounded patterns) used to ship
  inline in the vendored copy of the canonical scrubber, leaking the entire
  OLD→NEW mapping into the public mirror as a bounded deanonymization oracle.
  The mapping table is now declared canonical-only and the public mirror's
  scrubber loads cleanly with an identity-fallback table.
- A new transform `dotfiles_reference_scrub` covers residual `dotfiles/...`
  namespace references that the prior `path_scrub` didn't catch — `.claude/`,
  `.github/`, `docs/`, `mcp-servers/`, `SST3-metrics/` — plus drops a
  multi-line operator-only credential rotation runbook from the public copy of
  WORKFLOW.md and drops backtick-wrapped auto-memory file references from
  ANTI-PATTERNS.md.

### Dead code + zombie removal

- Removed 411 LOC of voice-tells enforcement code (3 scripts + a pre-commit
  hook block) that was wired against a non-existent `cv-linkedin/` directory
  in this mirror. The scripts still ship to consumer mirrors that actually
  host `cv-linkedin/` content.
- Removed a zombie `github/` directory (no leading dot) with 2 CI YAMLs that
  GitHub Actions ignored since this repo's first commit (Actions only reads
  `.github/`).
- Retired `stage5-completeness.yml` (30 historical runs, all skipped) and
  revoked the unused `DOTFILES_READ_TOKEN` Personal Access Token that backed
  it.

### Structural sync

- Mirrored skill files (`claude/commands/Leader.md`, `SST3-solo.md`) used to
  reference a canonical-only pre-loader script (`load-stage-rules.sh`) that
  adopters would hit ENOENT on. The transform now rewrites those invocations
  to inline adopter-facing instructions: read the tagged sections of
  `standards/STANDARDS.md` / `ANTI-PATTERNS.md` / `workflow/WORKFLOW.md`
  directly via the `<!-- stages: N -->` HTML-comment markers.
- Vendored a new `claude/hooks/` directory with 9 Claude Code PreToolUse +
  session hooks (canonical-mirror sync guards, destructive-op guards, branch
  guards, grep-before-write nudges, session-context injector, subagent RESULT
  parser, Tier-A AC binding gate, issue-body privacy gate, plus a shared
  branch/issue-detection library). All hooks pass per-hook secret-scan
  audits; no operator-machine-only paths or private references leaked
  through.
- Promoted `reference/lane-selection.md` from canonical-only to a public
  vendored file; fixed a broken `../dotfiles/SST3/reference/` self-reference
  in `reference/tool-selection-guide.md` to a plain sibling relative path.
- Declared 3 harness-only reference docs (`building-skills-guide.md`,
  `failed-experiments.md`, `quality-metrics.md`) as `harness_only_files` in
  the canonical manifest — these are community-PR-authored adopter guides
  with no canonical sibling needed. The manifest validator now enforces
  schema on the new field.
- Declared 2 canonical-side regression-test fixture directories as
  `unmirrored_canonical_files` so the public mirror has visibility on the
  intentional exclusion.
- Added `MIRROR-CONTRACT.md` — an adopter-facing description of the
  canonical-mirror governance contract: how propagation works, what gets
  scrubbed, files that exist only in mirror vs only in canonical, and how
  adopters report sync drift.

### Public-facing surface refresh

- README quantitative claims now reflect actual post-revamp counts: 16
  pre-commit hooks (was 14), 73 scripts (was 23), 40 wrapper-lane bash
  scripts (was 38+), 32 frozen-fixture self-test (was 25).
- New `## Stage-4 Extracts` README section narrating the 9-file
  `standards/stage-4/` directory introduced in the revamp.
- This CHANGELOG.md (new file).

## 2026-05-21 — Canonical revamp pickup (#497 + #498)

The canonical side ran two paired refactors:

- **Privacy + cleanup pass**: word-boundary regex for 3-char tokens (`NUC`,
  bare `Hoi`) where substring replace would collateral-damage longer words;
  expanded operator-identity scrub rules; new public-repo secret scanner with
  5-tier amplification.
- **Cut-and-tag refactor**: STANDARDS.md / ANTI-PATTERNS.md / WORKFLOW.md
  tagged with per-stage `<!-- stages: -->` HTML comments so a per-stage
  loader can emit only the relevant subset at session start (~28K bytes vs
  ~50K full canonical at Stage 1). The 9 stage-4 procedure extracts under
  `standards/stage-4/` were carved out in the same pass to keep the main
  STANDARDS file inside its token budget.

This public mirror picked up the propagated content shortly after the
canonical merge. See `claude/commands/Leader.md` Stage-by-stage sections for
the per-stage reading directives, and the 9 `standards/stage-4/` extracts
for the procedural payloads.

---

For the canonical-side change log + pre-revamp history, see the dotfiles
operator repository. Cross-references to canonical issue numbers (e.g.
`#497`, `#498`, `#501`) refer to the canonical issue tracker; on this public
mirror they are documentary only.
