#!/usr/bin/env bash
# feedback-banned-channel-488 fixture (dotfiles#488 AC 3.3 + AC 5.3(a)).
#
# Opposite-scoping guard: the Fix-C rewire makes commit-time validation
# PER-FILE, but it MUST still be the strict validate_record() — a
# malformed / channel-violating feedback file STILL fails its own
# author's commit post-fix (the governance invariant the Issue forbids
# weakening). The rewired commit-stage hook entry IS
# `python3 feedback_parser.py <path>`, so this fixture exercises that
# exact binary:
#   (a) AC 3.3   — a structurally-canonical file whose ONLY defect is a
#                  forward-preference channel phrase ("from now on")
#                  is REJECTED                                  -> exit != 0
#   (b) AC 5.3(a)— a structurally-malformed file (bare `## Stage 1`
#                  heading, the dotfiles#486/#488 halt class) is
#                  REJECTED                                      -> exit != 0
# Assets are non-conforming names; run.sh copies them to a conforming
# feedback-test-1.md (filename<->FM parity) in a temp dir. Exit 0 = the
# governance invariant holds; exit 1 = it was weakened (opposite-scoping).

set -euo pipefail

# dotfiles#552 AC 3.2 — sibling-relative walk: `scripts/` is a sibling of
# test-fixtures/ in BOTH the nested canonical and flattened mirror layouts,
# so 2-up-into-scripts is invariant. The old 3-up-to-repo-root then
# /scripts/ re-encoded the nested layout and overshot in the mirror.
SCRIPTS_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
PARSER="$SCRIPTS_DIR/feedback_parser.py"

# dotfiles#552 AC 3.2 — fail LOUD when the subject is absent. Without this,
# a missing target made assertions that merely expect a NON-ZERO exit pass
# vacuously (file-not-found is also non-zero), so the fixture reported
# "assertions passed" while testing nothing at all.
[ -f "$PARSER" ] || { echo "FIXTURE-ABORT: $PARSER not found at $PARSER" >&2; exit 2; }
HERE="$(dirname "$0")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rc() { set +e; "$@" >/dev/null 2>&1; echo $?; set -e; }

# --- (a) banned-channel phrase still rejected (AC 3.3) ---
cp "$HERE/banned.md" "$WORK/feedback-test-1.md"
bc=$(rc python3 "$PARSER" "$WORK/feedback-test-1.md")
if [[ "$bc" == "0" ]]; then
    echo "FAIL: (a) banned-channel feedback file expected per-file validate exit != 0, got 0 — CHANNEL-SEPARATION WEAKENED (opposite-scoping)"
    exit 1
fi
echo "PASS: (a) banned-channel phrase 'from now on' still rejected by per-file validate exit $bc (AC 3.3) [bc=$bc]"

# --- (b) structurally-malformed bare heading still rejected (AC 5.3(a)) ---
cp "$HERE/malformed.md" "$WORK/feedback-test-1.md"
mc=$(rc python3 "$PARSER" "$WORK/feedback-test-1.md")
if [[ "$mc" == "0" ]]; then
    echo "FAIL: (b) malformed bare-'## Stage 1' feedback file expected per-file validate exit != 0, got 0 — STRICT PARSER WEAKENED (opposite-scoping)"
    exit 1
fi
echo "PASS: (b) malformed bare-'## Stage 1' file still fails its own author's commit, per-file validate exit $mc (AC 5.3(a)) [mc=$mc]"

echo "RECORDED EXIT CODES: bc=$bc mc=$mc"
echo "OK: feedback-banned-channel-488 fixture (2/2 assertions passed)"
