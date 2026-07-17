#!/usr/bin/env bash
# sst3-code-callers-transitive.sh — BFS reverse-call lookup with depth.
#
# Usage:   sst3-code-callers-transitive.sh <symbol> <lang> [--depth=N]
# Example: sst3-code-callers-transitive.sh foo python --depth=3
# Output:  NDJSON, one record per visited symbol per depth level:
#          {file, line, symbol, depth, path:[chain]}
#          path: chain of symbol names from <symbol> (depth 0) to current.
#          line: 1-indexed editor line of the call site (#547).
#          symbol: the innermost def whose byte range CONTAINS the call site
#          (true AST byte-containment attribution, #547 AC 5.2); calls outside
#          every def attribute to <top-level>.
# Engines: ast-grep two-pass byte-containment index (ONE unified call-site
#          scan + ONE def scan per language family, awk innermost join) + jq.
# Default depth: 2.
#
# Rationale (#447 Phase 8): single-hop callers leaves auditors hand-stitching
# chains. This wrapper enumerates the BFS with bounded depth so subagents
# get a complete blast-radius graph in one call.

set -euo pipefail

# shellcheck source=./sst3-bash-utils.sh
source "$(dirname "$0")/sst3-bash-utils.sh"
export LC_ALL=C
SST3_EMITTED_COUNT=0

on_sigterm() {
    jq -nc --arg n "sst3-code-callers-transitive" --argjson e "$SST3_EMITTED_COUNT" \
        '{kind:($n + "-killed"), reason:"sigterm", partial_records:$e}'
    exit 143
}
trap on_sigterm SIGTERM
# (EXIT trap registered later, after $QUEUE/$VISITED tmpfiles are created —
# combines tmpfile cleanup with wrapper_sentinel to avoid overwriting the
# sentinel registration. Ralph Tier 3 FAIL C.)

DEPTH=2
PATHS_FROM=""
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --depth=*)
            DEPTH="${1#--depth=}"
            shift
            ;;
        --paths-from)
            PATHS_FROM="${2:-}"
            shift 2 || break
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#ARGS[@]} -lt 2 ]]; then
    echo "ERROR: usage: $(basename "$0") <symbol> <lang> [--depth=N] [--paths-from <ndjson>]" >&2
    exit 64
fi
if [[ ! "$DEPTH" =~ ^[0-9]+$ ]] || [[ "$DEPTH" -lt 1 ]] || [[ "$DEPTH" -gt 5 ]]; then
    echo "ERROR: --depth must be 1..5 (got: $DEPTH)" >&2
    exit 64
fi

# Stage 5 fix — was accepting --paths-from but never applying it (SC2034).
activate_paths_from_filter "$PATHS_FROM"

SYMBOL="${ARGS[0]}"
LANG_RAW="${ARGS[1]}"
assert_safe_identifier "$SYMBOL"
LANG=$(normalise_lang "$LANG_RAW")

if ! command -v jq >/dev/null 2>&1; then
    echo 'ERROR: jq not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi
if ! command -v ast-grep >/dev/null 2>&1; then
    echo 'ERROR: ast-grep not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi

# #547 AC 5.1 (D8): two-pass byte-containment index, built ONCE before the
# BFS — replaces the per-symbol callers.sh re-invocation crawl (2 full-repo
# ast-grep scans per discovered symbol per depth — the pre-#546 impact.sh
# class) and the lexical-backward enclosing_fn awk heuristic (which
# misattributed top-level calls to the lexically preceding def and fed a
# 0-indexed line into 1-indexed awk NR).
#   Pass A — ONE unified '$CALLEE($$$)' scan per language in the family: a
#   bare metavariable callee position matches identifier AND receiver-form
#   callees in one scan (the impact.sh build_caller_index precedent).
#   Pass B — all defs via impact.sh's per-language EXTRACT_RULE (#546 —
#   reused verbatim, not forked).
#   Join — innermost def whose byte range contains the call (max defStart
#   with defEnd >= callEnd), none → <top-level>; awk containment join.
# Callee keys use the impact.sh normalization ('?'→'', '::'→'.', last dotted
# component) so rust scoped calls (crate::util::helper()) resolve. ts/tsx/js
# share ONE 'jsfam' bucket (#547 AC 5.4 — a .ts def called from .tsx
# resolves); python/rust are single-language families. Emitted lines are
# born 1-INDEXED editor lines (#547 AC 5.5).
case "$LANG" in
    typescript|tsx|javascript) FAM_LANGS="typescript tsx javascript" ;;
    *) FAM_LANGS="$LANG" ;;
esac

# shellcheck disable=SC2016  # $NAME is an ast-grep meta-var, not shell
extract_rule_for() {
    case "$1" in
        python)
            printf '%s' 'id: impact-defs
language: python
rule:
  kind: function_definition
  has:
    field: name
    pattern: $NAME' ;;
        typescript|tsx|javascript)
            printf 'id: impact-defs\nlanguage: %s\nrule:\n  any:\n    - kind: function_declaration\n    - kind: method_definition\n    - kind: variable_declarator\n  has:\n    field: name\n    pattern: $NAME\n' "$1" ;;
        rust)
            printf '%s' 'id: impact-defs
language: rust
rule:
  kind: function_item
  has:
    field: name
    pattern: $NAME' ;;
    esac
}

declare -A CALLSITES_BY_CALLEE
build_containment_index() {
    local lang calls_tmp defs_tmp joined_tmp
    calls_tmp=$(mktemp)
    defs_tmp=$(mktemp)
    joined_tmp=$(mktemp)
    local ag_raw ag_rc
    ag_raw=$(mktemp)
    for lang in $FAM_LANGS; do
        # Pass A — call sites: file, callStart, callEnd, 1-indexed line, key.
        # #547 AC 6.1: buffer-then-check — the rc gate runs BEFORE jq sees the
        # stream (rc 1 = zero-matches stays a benign empty; rc >= 2 = engine
        # present but broken → -error record + exit 0, EXIT trap still fires).
        ag_rc=0
        # shellcheck disable=SC2016
        ast-grep run --pattern '$CALLEE($$$)' --lang "$lang" --json=stream > "$ag_raw" 2>/dev/null || ag_rc=$?
        ast_grep_check_rc "sst3-code-callers-transitive" "$ag_rc" \
            || { rm -f "$ag_raw" "$calls_tmp" "$defs_tmp" "$joined_tmp"; exit 0; }
        jq -r '[.file,
                (.range.byteOffset.start | tostring),
                (.range.byteOffset.end | tostring),
                ((.range.start.line + 1) | tostring),
                (.metaVariables.single.CALLEE.text // "")] | @tsv' < "$ag_raw" \
            | awk -F'\t' '$5 != "" {
                  gsub(/\?/, "", $5); gsub(/::/, ".", $5)
                  n = split($5, a, "."); key = a[n]
                  if (key ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/)
                      print $1 "\t" $2 "\t" $3 "\t" $4 "\t" key
              }' >> "$calls_tmp"
        # Pass B — defs: file, defStart, defEnd, name.
        ag_rc=0
        ast-grep scan --inline-rules "$(extract_rule_for "$lang")" --json=stream > "$ag_raw" 2>/dev/null || ag_rc=$?
        ast_grep_check_rc "sst3-code-callers-transitive" "$ag_rc" \
            || { rm -f "$ag_raw" "$calls_tmp" "$defs_tmp" "$joined_tmp"; exit 0; }
        jq -r '[.file,
                (.range.byteOffset.start | tostring),
                (.range.byteOffset.end | tostring),
                (.metaVariables.single.NAME.text // "")] | @tsv' < "$ag_raw" \
            | awk -F'\t' '$4 ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/' >> "$defs_tmp"
    done
    rm -f "$ag_raw"
    # Innermost-containment join: for each call, the containing def with the
    # greatest start offset; none → <top-level>.
    awk -F'\t' '
        FNR == NR {
            nd[$1]++
            ds[$1, nd[$1]] = $2 + 0
            de[$1, nd[$1]] = $3 + 0
            dn[$1, nd[$1]] = $4
            next
        }
        {
            file = $1; cs = $2 + 0; ce = $3 + 0; line = $4; key = $5
            best = -1; encl = "<top-level>"
            for (i = 1; i <= nd[file]; i++) {
                if (ds[file, i] <= cs && de[file, i] >= ce && ds[file, i] > best) {
                    best = ds[file, i]
                    encl = dn[file, i]
                }
            }
            print key "\t" file "\t" line "\t" encl
        }' "$defs_tmp" "$calls_tmp" > "$joined_tmp"
    local key file line encl
    while IFS=$'\t' read -r key file line encl; do
        [[ -z "$key" ]] && continue
        CALLSITES_BY_CALLEE["$key"]+="${file}"$'\t'"${line}"$'\t'"${encl}"$'\n'
    done < "$joined_tmp"
    rm -f "$calls_tmp" "$defs_tmp" "$joined_tmp"
}

# BFS state. Use a queue (text file) and a visited set (text file).
QUEUE=$(mktemp)
VISITED=$(mktemp)
# Combine tmpfile cleanup with wrapper_sentinel for EXIT (Ralph Tier 3 FAIL C).
trap 'rm -f "$QUEUE" "$VISITED"; wrapper_sentinel "sst3-code-callers-transitive" "$SST3_EMITTED_COUNT" "caller"' EXIT
trap 'rm -f "$QUEUE" "$VISITED"' INT TERM

build_containment_index

# Each queue entry: SYMBOL\tDEPTH\tPATH(comma-separated chain)
printf '%s\t0\t%s\n' "$SYMBOL" "$SYMBOL" > "$QUEUE"
echo "$SYMBOL" > "$VISITED"

while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    sym=$(printf '%s' "$entry" | cut -f1)
    cur_depth=$(printf '%s' "$entry" | cut -f2)
    cur_path=$(printf '%s' "$entry" | cut -f3)
    [[ -z "$sym" ]] && continue

    if (( cur_depth >= DEPTH )); then
        continue
    fi

    while IFS=$'\t' read -r file line encl; do
        [[ -z "$file" ]] && continue

        next_depth=$((cur_depth + 1))
        next_path="$cur_path,$encl"
        chain_json=$(printf '%s' "$next_path" | jq -Rc 'split(",")')

        jq -nc --arg f "$file" --argjson l "$line" --arg s "$encl" \
            --argjson d "$next_depth" --argjson p "$chain_json" \
            '{file:$f, line:$l, symbol:$s, depth:$d, path:$p}'
        SST3_EMITTED_COUNT=$((SST3_EMITTED_COUNT + 1))

        if [[ "$encl" != "<top-level>" ]] && ! grep -Fxq "$encl" "$VISITED"; then
            echo "$encl" >> "$VISITED"
            if [[ "$encl" =~ ^[a-zA-Z_][a-zA-Z0-9_.]*$ ]]; then
                printf '%s\t%s\t%s\n' "$encl" "$next_depth" "$next_path" >> "$QUEUE"
            fi
        fi
    done < <(printf '%s' "${CALLSITES_BY_CALLEE[$sym]:-}")
done < "$QUEUE"

exit 0
