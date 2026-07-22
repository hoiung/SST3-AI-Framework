#!/usr/bin/env python3
"""sst3-privacy-scan-issue-body.py — F-13 Issue-body privacy gate (#498 AC 2.4-2.6c).

Scans an Issue body for irreversible privacy leaks BEFORE mcp__github__create_issue
or mcp__github__update_issue fires. Catches the dotfiles#497 class of leak (long
numeric item IDs, business-identifier substrings, private filesystem paths,
operator-known account usernames) before it lands in a public-facing artefact.

Pattern policy (AC 2.6c PRIVACY BOUNDARY):
  This script body contains ONLY generic regex shapes — `[0-9]{12,18}`, MPN
  character-class patterns, Windows path regex with `[a-z]` drive letters, etc.
  Literal identifier substrings (operator usernames, business names, dev-machine
  filesystem prefixes) are NEVER baked in; they load at runtime from the
  canonical blocklist file at:
    scripts/.secret-blocklist-canonical
  This matches the precedent in check-public-repo-secrets.py — both scripts are
  in `unmirrored_canonical_files` per the propagate-mirrors manifest because the
  blocklist itself is the sensitive surface.

Exit codes:
  0  clean — no patterns matched
  1  blocked — at least one match; STDOUT lists matches
  2  usage error

Usage:
  python3 sst3-privacy-scan-issue-body.py --body-file <path>
  cat body.md | python3 sst3-privacy-scan-issue-body.py --stdin
  python3 sst3-privacy-scan-issue-body.py --body-file body.md --section dotfiles
  python3 sst3-privacy-scan-issue-body.py --body-file body.md --allowlist .secret-allowlist
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable

# dotfiles#552 AC 3.2 — the blocklist is a SIBLING of this script, so resolve it
# as one. Walking up to a repo root and back down re-encoded the nested canonical
# layout: in the FLATTENED public mirror (one level shallower) it pointed outside
# the repository entirely, so the not-found warning below named a path that was
# never the right place to look in that layout. Sibling resolution is invariant
# across both layouts.
DEFAULT_BLOCKLIST = Path(__file__).resolve().parent / ".secret-blocklist-canonical"

# Generic regex shapes — every pattern below uses character classes / counts only.
# No literal identifier substrings appear in this script body (AC 2.6c).
GENERIC_PATTERNS: dict[str, re.Pattern[str]] = {
    # Long numeric strings 12-18 digits: eBay item IDs / Seagate serial-shapes /
    # other ecommerce identifiers. Word-boundary anchored so phone numbers and
    # ISO timestamps don't false-positive.
    "long_numeric_id": re.compile(r"(?<![0-9])[0-9]{12,18}(?![0-9])"),
    # MPN-shape patterns: prefix letters + digits + suffix letters, typical of
    # hard-drive part numbers. Generic char-class form.
    "mpn_shape": re.compile(
        r"\b[A-Z]{2,4}[0-9]{4,8}[A-Z]{1,6}[0-9]*[A-Z]*\b"
    ),
    # Windows user-profile path with arbitrary drive letter (drive letter is a
    # char class — no literal `c` here).
    "windows_user_path": re.compile(r"/mnt/[a-z]/Users/", re.IGNORECASE),
    # Cloud-sync mounted path patterns. The literal directory names ("UserHome",
    # "UserHome", "UserHome") are NOT in the script — they load from the
    # blocklist file. Generic shape catches the "Drive/" suffix as a fallback.
    "drive_root_suffix": re.compile(r"\b[A-Z][a-zA-Z]+ Drive/", re.IGNORECASE),
}


def load_blocklist(path: Path, section: str | None) -> list[str]:
    """Load literal blocklist entries from the canonical file.

    The file is INI-ish: section headers `# [name]`, blank/comment lines ignored,
    every other line is a literal. Returns the union of `[shared]` plus the
    requested section. The script body never contains these literals; they live
    in the blocklist file (a separate, gitignore-controlled surface).
    """
    if not path.is_file():
        # Loud-degrade per AP #12 — operator must know the literal-scan layer is
        # disabled. Generic regex patterns still fire, so this is not a silent
        # PASS, but the operator-account/MPN/item-ID partition is invisible.
        print(
            f"sst3-privacy-scan-issue-body: WARNING — blocklist not found at {path}; "
            f"literal-scan disabled, generic regex patterns still active",
            file=sys.stderr,
        )
        return []
    literals: list[str] = []
    current_section: str | None = None
    want = {"shared"}
    if section:
        want.add(section.lower())
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            # Section header form: `# [name]`
            m = re.match(r"#\s*\[(?P<name>[^\]]+)\]\s*$", line)
            if m:
                current_section = m.group("name").lower()
            continue
        if current_section is None:
            # Pre-section literals go into [shared] by convention.
            current_section = "shared"
        if current_section in want:
            literals.append(line)
    # De-dup preserving order.
    seen: set[str] = set()
    out: list[str] = []
    for lit in literals:
        if lit not in seen:
            seen.add(lit)
            out.append(lit)
    return out


def load_allowlist(path: Path | None) -> set[str]:
    """Allowlist entries are substring matches; their match is suppressed."""
    if not path or not path.is_file():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip() and not line.strip().startswith("#")
    }


def scan(
    body: str,
    blocklist: Iterable[str],
    allowlist: set[str],
) -> list[tuple[str, int, str]]:
    """Return list of (pattern_name, line_number, matched_text) violations."""
    findings: list[tuple[str, int, str]] = []
    lines = body.splitlines()

    # Generic-pattern scan.
    for name, pat in GENERIC_PATTERNS.items():
        for idx, line in enumerate(lines, start=1):
            for m in pat.finditer(line):
                text = m.group(0)
                if any(allowed in text for allowed in allowlist):
                    continue
                findings.append((name, idx, text))

    # Literal blocklist scan (case-insensitive substring).
    body_lower_lines = [(idx, line.lower()) for idx, line in enumerate(lines, start=1)]
    for literal in blocklist:
        needle = literal.lower()
        if not needle:
            continue
        for idx, line_lower in body_lower_lines:
            if needle in line_lower:
                if any(allowed.lower() in needle for allowed in allowlist):
                    continue
                findings.append(("blocklist_literal", idx, literal))

    return findings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--body-file", type=Path, help="Path to Issue body file")
    src.add_argument("--stdin", action="store_true", help="Read Issue body from stdin")
    parser.add_argument(
        "--section",
        default="dotfiles",
        help="Blocklist section to load alongside [shared]. Default: dotfiles.",
    )
    parser.add_argument(
        "--blocklist",
        type=Path,
        default=DEFAULT_BLOCKLIST,
        help="Path to canonical blocklist file.",
    )
    parser.add_argument(
        "--allowlist",
        type=Path,
        default=None,
        help="Optional per-repo allowlist file (substring suppression).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of human-readable text.",
    )
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2

    if args.body_file:
        if not args.body_file.is_file():
            print(f"ERROR: body file not found: {args.body_file}", file=sys.stderr)
            return 2
        body = args.body_file.read_text(encoding="utf-8", errors="replace")
    else:
        body = sys.stdin.read()

    blocklist = load_blocklist(args.blocklist, args.section)
    allowlist = load_allowlist(args.allowlist)

    findings = scan(body, blocklist, allowlist)

    if not findings:
        return 0

    if args.json:
        import json

        json.dump(
            {
                "blocked": True,
                "violation_count": len(findings),
                "findings": [
                    {"pattern": name, "line": line, "match": match}
                    for name, line, match in findings
                ],
            },
            sys.stdout,
        )
        sys.stdout.write("\n")
    else:
        print(
            "F-13 PRIVACY GATE: Issue body contains privacy-sensitive substrings",
            file=sys.stderr,
        )
        print(f"  violations: {len(findings)}", file=sys.stderr)
        for name, line, match in findings:
            print(f"  line {line}: [{name}] {match!r}", file=sys.stderr)
        print(
            "\n  Remediation: scrub the Issue body OR add a `.secret-allowlist` entry "
            "if the match is a confirmed false positive.",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
