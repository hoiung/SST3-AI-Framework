#!/usr/bin/env bash
# AP #22 enforcement: catch unprotected `cd <path> && git ...` patterns in
# scripts under scripts/ + scripts/. Subshell-protected forms
# `(cd <path> && git ...)` are exempt; `git -C <path>` is preferred.
#
# Wired as a pre-commit hook. Exits 1 if any violation found.
#
# Issue: hoiung/dotfiles#460 Phase 9 AC 9.7.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIRS=("$ROOT/SST3/scripts" "$ROOT/scripts")

# Pattern: line starts with optional whitespace, has `cd <non-amp>` followed by
# `&& git ` — but NOT inside subshell parens. We can't detect parens with grep
# alone; we use a 2-step approach: first list candidates, then exclude lines
# containing `(cd `.
violations=()
for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r line; do
        # Skip if subshell-protected (contains literal `(cd `).
        if echo "$line" | grep -q '(cd '; then
            continue
        fi
        # Strip the file:lineno: prefix from grep -n output to inspect content.
        content=$(echo "$line" | sed -E 's/^[^:]+:[0-9]+://')
        # Skip pure-comment lines (bash `#` or shell-script `# `).
        if echo "$content" | grep -qE '^[[:space:]]*#'; then
            continue
        fi
        # Skip lines inside heredoc/string-literal contexts where `cd` is data
        # not a command. Heuristic: skip lines with backticks-only or single-quote
        # only context surrounding `cd`. Cheap detection of common false positives.
        if echo "$content" | grep -qE '`cd [^&]+&& *git'; then
            continue
        fi
        violations+=("$line")
    done < <(grep -rnE 'cd [^&]+&& *git ' "$d" 2>/dev/null || true)
done

if [[ ${#violations[@]} -eq 0 ]]; then
    exit 0
fi

echo "============================================================" >&2
echo "AP #22 violation(s) detected (cross-repo cd && git not subshell-protected):" >&2
echo "============================================================" >&2
for v in "${violations[@]}"; do
    echo "  $v" >&2
done
echo "" >&2
echo "Fix: use 'git -C <path> <subcmd>' (preferred) or '(cd <path> && git ...)' (subshell-protected)." >&2
echo "Canonical: standards/ANTI-PATTERNS.md AP #22." >&2
exit 1
