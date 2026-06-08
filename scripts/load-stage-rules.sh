#!/usr/bin/env bash
# load-stage-rules.sh — F-Phase-4 per-stage canonical loader (#498 AC 4.6).
#
# WHAT  Outputs the subset of SST3 canon needed by a specific /Leader stage.
#       Reads STANDARDS.md + ANTI-PATTERNS.md + WORKFLOW.md, extracts:
#         (1) Every section tagged `<!-- stages: always -->`
#         (2) Every section tagged with the requested stage number
#       For any stage N (1-5), additionally includes `standards/stage-N/*.md`
#       if that directory exists (#516 AC 1.1 — generalised from stage-4-only).
#       Concatenates to stdout for the agent's context loader to read.
#
# WHY   Pre-refactor, the agent loaded the full STANDARDS.md (1420 lines, ~49K
#       tokens) + ANTI-PATTERNS.md (645 lines, ~22K tokens) at every stage,
#       even when most sections were stage-irrelevant. Per-stage tagging +
#       this loader reduce the per-stage in-context load by ~50-70% while
#       preserving always-load sections (privacy / force-push / branch-deletion
#       / voice contamination — the Layer-2 Angle C carve-out).
#
# USAGE
#   bash scripts/load-stage-rules.sh <N>          # N = 1..5
#   bash scripts/load-stage-rules.sh always       # always-load subset
#
# EXIT  0 = stdout populated; 1 = invalid stage / canon files missing.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <stage-number-1-to-5 | always>" >&2
  exit 1
fi
STAGE_ARG="$1"

case "$STAGE_ARG" in
  1|2|3|4|5|always) : ;;
  *)
    echo "error: stage must be 1-5 or 'always', got: $STAGE_ARG" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
  # Fallback when invoked outside a git worktree (e.g. via symlink).
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

STANDARDS_MD="$REPO_ROOT/standards/STANDARDS.md"
ANTIPATTERNS_MD="$REPO_ROOT/standards/ANTI-PATTERNS.md"
WORKFLOW_MD="$REPO_ROOT/workflow/WORKFLOW.md"
STANDARDS_DIR="$REPO_ROOT/SST3/standards"

for f in "$STANDARDS_MD" "$ANTIPATTERNS_MD" "$WORKFLOW_MD"; do
  if [[ ! -f "$f" ]]; then
    echo "error: canon file missing: $f" >&2
    exit 1
  fi
done

# Extraction logic lives in _load_stage_rules.py — single source of truth for
# the per-stage section-extraction algorithm. The .py shares regex constants
# with check-stage-tags.py via sst3_stage_tag_parser (#498 Stage 5 L1C F3).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/_load_stage_rules.py" "$STAGE_ARG" "$STANDARDS_MD" "$ANTIPATTERNS_MD" "$WORKFLOW_MD"

# Per-stage cluster files: any standards/stage-N/ directory is loaded for
# stage N (#516 AC 1.1 — generalised from the prior stage-4-only special case).
# The loader globs stage-{1,2,3,4,5}/*.md when the directory exists; 'always'
# has no cluster dir. Backward-compatible: stage-4 still loads stage-4/*.md.
if [[ "$STAGE_ARG" =~ ^[1-5]$ ]]; then
  STAGE_DIR="$STANDARDS_DIR/stage-$STAGE_ARG"
  if [[ -d "$STAGE_DIR" ]]; then
    for f in "$STAGE_DIR"/*.md; do
      [[ -f "$f" ]] || continue
      printf '\n<!-- ===== %s ===== -->\n' "${f#$REPO_ROOT/}"
      cat "$f"
    done
  fi
fi
