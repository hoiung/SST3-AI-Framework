#!/usr/bin/env python3
"""
Validate the metadata fields a Stage 1 research file MUST declare so that
Stages 2/3/4/5 can carry them forward without re-classifying (TB-2
single-declaration-carries-forward).

Required fields (grammar tolerates `**field**:` markdown bold wrapping):
  graph_applicable: <true|false|hybrid> [(reason: <text>)]
  invoked_skill:    <name|none>
  skill_canonical_files: <yaml-list-or-prose-list>   (empty OK iff invoked_skill==none)

Accepted (AC 2.7): `graph_applicable: false` / `graph_applicable: hybrid` /
  `graph_applicable: true`. REJECTED: backtick-wrapped values, freeform synonyms,
  inline YAML comments inside a scalar value.

Optional corpus-coverage fields (dotfiles#528 AC 6.3): a research file MAY also
  declare `corpus_glob:` + `files_read:` / `files_total:`. When present, a
  PARTIAL read (files_read < files_total) without a `sampling_justification:`
  fails. files_total = COMMITTED file count (`git ls-files <corpus_glob> | wc -l`),
  never the dirty worktree. Absent => skipped (backward-compatible).

Exits 0 on all-valid; exits 1 with one actionable message per failure.

Issue: hoiung/dotfiles#460 Phase 4 (Track W6 — surfaced by Layer-2 audit).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Field key regex tolerates leading/trailing markdown bold wrappers.
# Matches: `graph_applicable:`, `**graph_applicable**:`, `- graph_applicable:`,
#          `**graph_applicable**:` after bullet, etc.
FIELD_KEY = r"\**\s*{key}\s*\**"

GRAPH_VALUE_DOMAIN = {"true", "false", "hybrid"}

# dotfiles#522 AC 6.2: the `## Agreements Log` floor. A research file must carry
# an Agreements Log section with at least one bullet (the operator-agreement
# record the verifier panel reconciles against). This is a PRESENCE-only floor —
# content quality is judged by the verifier panel, never by this gate.
AGREEMENTS_LOG_HEADING_RE = re.compile(r"^##\s+Agreements\s+Log\s*$", re.MULTILINE)
# A bullet under the section: `- ...`, `* ...`, or `1. ...` (numbered).
_BULLET_RE = re.compile(r"^\s*(?:[-*]|\d+\.)\s+\S")
_H2_RE = re.compile(r"^##\s+")


def _has_agreements_log_with_bullet(content: str) -> bool:
    """True iff a `## Agreements Log` section exists AND holds >=1 list bullet.

    The section runs from its heading until the next `## ` heading (or EOF).
    HTML-comment lines (e.g. the extract-chat-agreements provenance comment) and
    blank lines do not count as bullets — a real agreement bullet is required.
    """
    m = AGREEMENTS_LOG_HEADING_RE.search(content)
    if m is None:
        return False
    rest = content[m.end():].splitlines()
    for line in rest:
        if _H2_RE.match(line):
            break  # next section starts — Agreements Log scope ended
        if _BULLET_RE.match(line):
            return True
    return False


def _strip_md_bold(s: str) -> str:
    """Strip markdown bold markers from a value (e.g. **hybrid** -> hybrid)."""
    return s.strip().lstrip("*").rstrip("*").strip()


def _find_field(content: str, key: str) -> tuple[int, str] | None:
    """
    Return (lineno, raw_value_after_colon) of the first occurrence of `key:`,
    or None if not found. Tolerates `**key**:` wrappers.

    For multi-line yaml-style list values (key: <empty>\n  - item\n  - item),
    folds the trailing bulleted lines into raw_value as a comma-joined string
    so downstream is_empty checks treat them as non-empty.
    """
    pattern = re.compile(rf"^\s*-?\s*{FIELD_KEY.format(key=re.escape(key))}\s*:(.*)$",
                         re.MULTILINE)
    m = pattern.search(content)
    if not m:
        return None
    lineno = content[:m.start()].count("\n") + 1
    same_line = m.group(1).strip()
    if same_line:
        return lineno, same_line
    # Empty same-line value — collect indented bullets from next lines.
    after = content[m.end():].splitlines()
    bullets: list[str] = []
    for line in after:
        if not line.strip():
            continue
        # Either an indented dash bullet `- foo` or any non-indented line breaks.
        if re.match(r"^\s+-\s+\S", line):
            bullets.append(line.strip()[2:].strip())
            continue
        break
    if bullets:
        return lineno, ", ".join(bullets)
    return lineno, ""


def _validate_corpus_coverage(content: str, path: Path) -> list[str]:
    """dotfiles#528 AC 6.3 — optional Stage-1 corpus-coverage gate.

    A research file MAY declare it swept a corpus via `corpus_glob:` plus
    `files_read:` / `files_total:`. When it does, a PARTIAL read
    (files_read < files_total) MUST carry a non-empty `sampling_justification:`
    — otherwise the gate fails (the pass-1-overflowed-6/8-slices failure this
    prevents). `files_total` is the COMMITTED file count
    (`git ls-files <corpus_glob> | wc -l`), NEVER the dirty worktree — an
    untracked parallel-session file would otherwise inflate the count and
    false-fail the gate.

    All three coverage fields absent => skip (the fields are optional and
    backward-compatible; pre-AC-6.3 research files are unaffected).
    """
    read_found = _find_field(content, "files_read")
    total_found = _find_field(content, "files_total")
    glob_found = _find_field(content, "corpus_glob")

    # No coverage claim signalled at all — nothing to gate.
    if read_found is None and total_found is None and glob_found is None:
        return []

    failures: list[str] = []

    def _as_int(found: tuple[int, str] | None, key: str) -> int | None:
        if found is None:
            failures.append(
                f"{path}: corpus-coverage declared (corpus_glob / files_read / "
                f"files_total) but `{key}` is missing — declare BOTH files_read "
                f"and files_total as integers (count files_total via "
                f"`git ls-files <corpus_glob> | wc -l`, committed files only)."
            )
            return None
        lineno, raw = found
        token = _strip_md_bold(raw).split()[0].rstrip(",;.") if raw.strip() else ""
        try:
            return int(token)
        except ValueError:
            failures.append(
                f"{path}:{lineno}: `{key}` value {token!r} is not an integer."
            )
            return None

    files_read = _as_int(read_found, "files_read")
    files_total = _as_int(total_found, "files_total")
    if files_read is None or files_total is None:
        return failures  # missing/non-int already reported

    just_found = _find_field(content, "sampling_justification")
    has_justification = (
        just_found is not None
        and _strip_md_bold(just_found[1]).lower() not in ("", "none", "n/a", "[]")
    )

    if files_read > files_total:
        failures.append(
            f"{path}: files_read ({files_read}) > files_total ({files_total}) — "
            f"impossible; count files_total from COMMITTED files "
            f"(`git ls-files <corpus_glob> | wc -l`), not the dirty worktree "
            f"(an untracked parallel-session file inflates the worktree count)."
        )
    elif files_read < files_total and not has_justification:
        failures.append(
            f"{path}: corpus coverage is partial (files_read {files_read} < "
            f"files_total {files_total}) but no `sampling_justification:` is "
            f"declared — read the full corpus, or add a `sampling_justification:` "
            f"field explaining why the sample is representative (dotfiles#528 AC 6.3)."
        )
    return failures


def validate(path: Path) -> list[str]:
    """Return list of human-readable failure messages; empty list on full pass."""
    if not path.exists():
        return [f"{path}: file does not exist"]
    content = path.read_text(encoding="utf-8-sig")
    failures: list[str] = []

    # graph_applicable
    found = _find_field(content, "graph_applicable")
    if found is None:
        failures.append(f"{path}: missing required field `graph_applicable` "
                        f"(allowed values: {sorted(GRAPH_VALUE_DOMAIN)})")
    else:
        lineno, raw = found
        # Value may be `<token>` or `<token> (reason: ...)` — extract first token.
        first_token = _strip_md_bold(raw.split("(")[0]).rstrip(",;.")
        if first_token.lower() not in GRAPH_VALUE_DOMAIN:
            failures.append(
                f"{path}:{lineno}: graph_applicable value {first_token!r} not in "
                f"{sorted(GRAPH_VALUE_DOMAIN)}"
            )

    # invoked_skill
    found_skill = _find_field(content, "invoked_skill")
    invoked_skill_value: str | None = None
    if found_skill is None:
        failures.append(f"{path}: missing required field `invoked_skill` "
                        f"(use `none` for pure-infrastructure tasks)")
    else:
        lineno, raw = found_skill
        invoked_skill_value = _strip_md_bold(raw).split()[0] if raw.strip() else ""
        if not invoked_skill_value:
            failures.append(f"{path}:{lineno}: invoked_skill value is empty")

    # skill_canonical_files
    found_files = _find_field(content, "skill_canonical_files")
    if found_files is None:
        failures.append(
            f"{path}: missing required field `skill_canonical_files` "
            f"(use `[]` or empty value when invoked_skill: none)"
        )
    else:
        lineno, raw = found_files
        # Value can be a yaml list `[a, b, c]` or `[]` or empty.
        is_empty = raw.strip() in ("", "[]", "(none)", "none", "n/a")
        if (
            invoked_skill_value
            and invoked_skill_value.lower() != "none"
            and is_empty
        ):
            failures.append(
                f"{path}:{lineno}: skill_canonical_files is empty but invoked_skill "
                f"is {invoked_skill_value!r} (must be `none` for empty list to be OK)"
            )

    # dotfiles#522 AC 6.2: `## Agreements Log` presence floor (verifier-led
    # chat reconciliation). Present + >=1 bullet, else exit 1 — content judged
    # by the verifier panel, not here.
    if not _has_agreements_log_with_bullet(content):
        failures.append(
            f"{path}: missing or empty `## Agreements Log` section "
            f"(dotfiles#522 chat-reconciliation floor: add the section with >=1 "
            f"operator-agreement bullet, sourced from "
            f"`scripts/extract-chat-agreements.py`)"
        )

    # dotfiles#528 AC 6.3: optional corpus-coverage assertion (skips cleanly
    # when the corpus_glob/files_read/files_total fields are absent).
    failures.extend(_validate_corpus_coverage(content, path))

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate Stage 1 research-file metadata fields "
            "(graph_applicable / invoked_skill / skill_canonical_files)."
        ),
    )
    # nargs="+" so the pre-commit `sst3-chat-reconciliation` hook (#522 AC 6.2)
    # can pass every matched committed research file in one invocation.
    parser.add_argument(
        "path", type=Path, nargs="+",
        help="Path(s) to research_<topic>_<date>.md file(s).",
    )
    args = parser.parse_args()

    all_failures: list[str] = []
    for path in args.path:
        failures = validate(path)
        if failures:
            all_failures.extend(failures)
        else:
            print(f"[OK] Stage 1 metadata valid: {path}")
    if not all_failures:
        return 0
    print("=" * 60, file=sys.stderr)
    print(f"STAGE 1 METADATA VALIDATION FAILED: {len(all_failures)} issue(s)", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    for msg in all_failures:
        print(f"  - {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
