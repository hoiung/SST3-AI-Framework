#!/usr/bin/env bash
# sst3-test-vacuity.sh — mechanical pre-Ralph vacuity sweep (#567 Phase 4).
#
# Detects assertions that CANNOT fail and allowlist entries whose reason covers
# more occurrences than it plausibly describes — the two defect classes measured
# on Issue #3 that cost LLM reviewer rounds to find by reading.
# Runs BEFORE Ralph Tier 1 dispatch (Leader.md Stage-4 step 6.5); its findings
# are fixed before any reviewer is spawned.
#
# Usage:   sst3-test-vacuity.sh [--count-in <doc> [--threshold N]] [--paths-from f] [file.py ...]
# Default: no positional files -> scans tests/**/*.py + test_*.py under CWD,
#          EXCLUDING any path under a `test-fixtures/` directory (frozen
#          known-answer corpora are intentionally vacuous positive controls;
#          pre-#567-T3-E3 the bare invocation scanned them and the gate was
#          red by default in its own repo). Explicit paths are never filtered.
# Detects (AST-based, per file):
#   assert-literal      assert of a truthy constant or non-empty
#                       tuple/list/dict/set literal (incl. the classic
#                       `assert (cond, "msg")` and a bare/implicitly-continued
#                       string after `assert`).
#   assert-or-true      assert whose test contains `... or True` (a truthy
#                       constant operand in an `or`).
#   assert-self-compare an assertion whose expected value is computed by the
#                       SAME expression it checks, under an UNFALSIFIABLE
#                       operator only (`==`, `<=`, `>=`, `is`). An
#                       always-FALSE self-compare (`!=`, `<`, `>`, `is not`)
#                       is deliberately NOT claimed: it reddens the suite
#                       itself, so it is not a silent-pass hazard (#567 T3
#                       S6a — flagging it under "cannot fail" was a
#                       mislabel; pinned by test-vacuity-detector-precision).
#   allowlist-overreach with --count-in <doc>: for each entry of an
#                       allowlist-shaped dict ({str: reason-str} assigned to a
#                       name matching ALLOW|EXEMPT|UNBOUND|REASON|WAIV|SKIP),
#                       count standalone occurrences of the key in <doc>;
#                       >= threshold (default 10) = the reason cannot plausibly
#                       describe them all (measured case: "4": "ordinals and
#                       list numbering" — reconciled to 33 occurrences, 24 of
#                       them Model=4, per the #567 dogfood reconciliation; the
#                       frozen allowlist fixture replicates the SHAPE with a
#                       constructed 32/20, not the exact figures — #567 T3 F9).
#                       Structured `word=KEY` hits are reported separately as
#                       the strongest overreach signal.
# NOT enumerated (blind BY CONSTRUCTION — mutation-verification.md sweep gate 2:
# a scanner declares what it cannot produce beside what it does; gate 5: the
# blindness is ASSERTED by the frozen test-vacuity-blindspots fixture, which
# expects exit 0 / 0 findings on exactly these forms and DRIFTS if a widening
# makes the scanner sensitive without updating this disclosure):
#   unittest-Call forms   self.assertTrue(True) / self.assertEqual(1, 1) — Call
#                         nodes, never ast.Assert; the scanner walks ast.Assert
#                         only.
#   pytest.raises no-op   `with pytest.raises(E): pass` — no assert node at all.
#   constant-foldable     `assert len([]) == 0` — sides equal after folding but
#                         not AST-identical, so assert-self-compare (ast.dump
#                         equality) cannot see it.
# These classes remain reviewer work (Ralph break-one-claim angle), not this
# script's. Found by #567 Ralph Tier-2 break-one-claim; disclosed per canon.
# Output:  STDOUT — NDJSON, one object per finding: {file, line, kind, detail}
#          STDERR — always emits the sentinel:
#                   "sst3-test-vacuity: scanned <N> file(s), <M> finding(s)"
# Exit:    0 = ran clean over >=1 scanned file, 1 = findings (this wrapper is a
#          GATE, not a triage reporter — AC 4.1/4.3 wire it pre-Tier-1, so
#          findings block), 2 = could-not-look (engine crashed / unparseable
#          file / USAGE ERROR on bad arguments / NOTHING SCANNED — a run that
#          scanned zero files proved nothing and must never read as clean;
#          #567 Ralph T3 F2+F4, mirrors sst3-check --strict semantics),
#          127 = engine missing.
set -uo pipefail
export LC_ALL=C

# shellcheck source=./sst3-bash-utils.sh
source "$(dirname "$0")/sst3-bash-utils.sh"

__PATHS_FROM_SST3=""
__ARGS_SST3=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --paths-from)
            # A missing operand must fail LOUD: the old `${2:-}` set the
            # filter to empty and broke out of parsing, so the run
            # reported clean instead of erroring (#567 T3 S6c).
            if [[ $# -lt 2 ]]; then
                echo "sst3-test-vacuity: USAGE ERROR: --paths-from requires a file argument" >&2
                exit 2
            fi
            __PATHS_FROM_SST3="$2"; shift 2;;
        *) __ARGS_SST3+=("$1"); shift;;
    esac
done
set -- "${__ARGS_SST3[@]+"${__ARGS_SST3[@]}"}"
activate_paths_from_filter "$__PATHS_FROM_SST3"

if ! command -v python3 >/dev/null 2>&1; then
    echo 'ERROR: python3 not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi

python3 - "$@" <<'PYEOF'
import ast, glob, json, re, sys

def emit(file, line, kind, detail):
    print(json.dumps({"file": file, "line": line, "kind": kind, "detail": detail}))

ALLOWLIST_NAME = re.compile(r"ALLOW|EXEMPT|UNBOUND|REASON|WAIV|SKIP", re.I)

def is_truthy_const(node):
    return isinstance(node, ast.Constant) and bool(node.value) and node.value is not False

def scan_asserts(path, tree):
    n = 0
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assert):
            continue
        t = node.test
        if isinstance(t, ast.Constant) and bool(t.value):
            kind = "assert-literal"
            what = "string literal" if isinstance(t.value, str) else repr(t.value)
            emit(path, t.lineno, kind, f"assert of truthy constant ({what}) cannot fail")
            n += 1
        elif isinstance(t, (ast.Tuple, ast.List)) and t.elts:
            emit(path, t.lineno, "assert-literal",
                 "assert of a non-empty tuple/list literal is always true (classic `assert (cond, \"msg\")`)")
            n += 1
        elif isinstance(t, ast.Dict) and t.keys:
            emit(path, t.lineno, "assert-literal",
                 "assert of a non-empty dict literal is always true")
            n += 1
        elif isinstance(t, ast.Set) and t.elts:
            emit(path, t.lineno, "assert-literal",
                 "assert of a non-empty set literal is always true")
            n += 1
        if isinstance(t, ast.BoolOp) and isinstance(t.op, ast.Or) and any(is_truthy_const(v) for v in t.values):
            emit(path, t.lineno, "assert-or-true", "`or <truthy constant>` makes this assertion unfalsifiable")
            n += 1
        if isinstance(t, ast.Compare):
            # Only UNFALSIFIABLE operators are vacuity findings (#567 T3
            # S6a): `x == x` / `x <= x` / `x >= x` / `x is x` cannot fail;
            # `x != x` / `x < x` / `x > x` / `x is not x` ALWAYS fail — the
            # suite itself reddens on them, so they are not a silent-pass
            # hazard and this gate deliberately does not claim them.
            left = ast.dump(t.left)
            for op, cmp_ in zip(t.ops, t.comparators):
                if ast.dump(cmp_) == left and isinstance(
                    op, (ast.Eq, ast.LtE, ast.GtE, ast.Is)
                ):
                    emit(path, t.lineno, "assert-self-compare",
                         "expected value is computed by the same expression it checks")
                    n += 1
                    break
    return n

def allowlist_dicts(tree):
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Dict):
            names = [t.id for t in node.targets if isinstance(t, ast.Name)]
            if not any(ALLOWLIST_NAME.search(nm) for nm in names):
                continue
            for k, v in zip(node.value.keys, node.value.values):
                if isinstance(k, ast.Constant) and isinstance(k.value, str) \
                   and isinstance(v, ast.Constant) and isinstance(v.value, str):
                    yield names[0], k.value, v.value, k.lineno

def scan_allowlist(path, tree, doc_path, doc_text, threshold):
    n = 0
    for dname, key, reason, lineno in allowlist_dicts(tree):
        esc = re.escape(key)
        # `=` is excluded from the standalone lookbehind so a `word=KEY` hit is
        # counted ONCE, in the structured bucket — double-counting would inflate
        # the total and misreport the measured shape.
        standalone = re.findall(rf"(?<![\w.=]){esc}(?![\w.])", doc_text)
        structured = re.findall(rf"\w+={esc}(?![\w.])", doc_text)
        total = len(standalone) + len(structured)
        if total >= threshold:
            emit(path, lineno, "allowlist-overreach",
                 f"{dname}[{key!r}] reason ({reason!r}) covers {total} occurrence(s) in {doc_path} "
                 f"({len(structured)} in structured word={key} contexts) — one reason cannot "
                 f"plausibly describe them all; scope the exemption per occurrence class")
            n += 1
    return n

args = sys.argv[1:]
def usage_error(msg):
    # Unusable arguments are a could-not-look, not a findings state: exit 2,
    # never the findings code 1 and never a raw traceback (#567 Ralph T3 F4).
    print(f"sst3-test-vacuity: USAGE ERROR: {msg}", file=sys.stderr)
    sys.exit(2)

count_in = None
threshold = 10
files = []
i = 0
while i < len(args):
    if args[i] == "--count-in":
        if i + 1 >= len(args):
            usage_error("--count-in requires a <doc> argument")
        count_in = args[i + 1]; i += 2
    elif args[i] == "--threshold":
        if i + 1 >= len(args):
            usage_error("--threshold requires an integer argument")
        try:
            threshold = int(args[i + 1])
        except ValueError:
            usage_error(f"--threshold expects an integer, got {args[i + 1]!r}")
        if threshold < 1:
            usage_error(f"--threshold must be >= 1, got {threshold}")
        i += 2
    else:
        files.append(args[i]); i += 1
explicit = bool(files)
if not files:
    files = sorted(set(glob.glob("tests/**/*.py", recursive=True) + glob.glob("**/test_*.py", recursive=True)))
    # Discovery-mode exclusion (#567 T3 E3): a `test-fixtures/` directory
    # holds frozen known-answer corpora that are INTENTIONALLY vacuous
    # (the gate's own positive controls), so a bare repo-root invocation
    # scanned its own fixtures and exited 1 on a clean tree — the
    # documented Leader.md step-6.5 gate was red BY DEFAULT in dotfiles.
    # Explicitly-passed paths are never filtered (the self-test drives
    # the fixtures by explicit path and must keep doing so).
    files = [f for f in files if "test-fixtures/" not in f.replace("\\", "/")]

doc_text = None
if count_in is not None:
    try:
        with open(count_in, encoding="utf-8", errors="replace") as fh:
            doc_text = fh.read()
    except OSError as e:
        usage_error(f"--count-in doc unreadable: {e}")

scanned = findings = 0
for path in files:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        tree = ast.parse(src, filename=path)
    except (OSError, SyntaxError) as e:
        # Could-not-look is loud, never a silent skip (Fail Fast / AP #7).
        print(f"sst3-test-vacuity: ENGINE CRASHED parsing {path}: {e}", file=sys.stderr)
        sys.exit(2)
    scanned += 1
    findings += scan_asserts(path, tree)
    if doc_text is not None:
        findings += scan_allowlist(path, tree, count_in, doc_text, threshold)

print(f"sst3-test-vacuity: scanned {scanned} file(s), {findings} finding(s)", file=sys.stderr)
if scanned == 0:
    # A run that scanned nothing proved nothing — exit 0 here would be the
    # vacuous PASS this very gate exists to reject (#567 Ralph T3 F2: a vacuous
    # file outside the discovery glob left 'scanned 0' at exit 0, byte-for-byte
    # a clean gate). Could-not-look exits 2, mirroring sst3-check --strict.
    mode = "explicit paths matched no scannable file" if explicit else \
        "bare discovery found no tests/**/*.py or **/test_*.py under CWD"
    print(
        f"sst3-test-vacuity: NOTHING SCANNED ({mode}) — nothing proven. "
        "Pass the diff's test files explicitly, or record skip-clean "
        "(no Python test surface in diff) instead of citing this run.",
        file=sys.stderr,
    )
    sys.exit(2)
sys.exit(1 if findings else 0)
PYEOF
