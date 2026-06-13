#!/usr/bin/env python3
"""
Extract the operator's genuine typed chat messages from a Claude Code session
transcript so a verifier panel can reconcile the implementation against what was
actually agreed in chat (vs only the Issue scope).

Claude Code records every session as newline-delimited JSON at
  ~/.claude/projects/<cwd-slug>/<session-uuid>.jsonl
where <cwd-slug> is the working directory with every `/` replaced by `-`
(e.g. /home/you/projects/my-app -> -home-you-projects-my-app).
The transcript survives compaction, so it is the authoritative record of what the
operator actually said — memory and handovers are not.

This script reads those JSONL files and recovers ONLY genuine operator-typed
turns, dropping harness-injected noise:
  - tool_result content parts (function outputs)
  - <system-reminder> / <command-*> / <local-command-*> / <bash-*> wrappers
  - skill-body injections (the rendered slash-command body sent as a user turn)
  - compaction summaries ("This session is being continued ...")
  - "[Request interrupted by user]" markers
  - isMeta / isSidechain turns (subagent sidechains, meta events)

The recovered messages are emitted as a `## Agreements Log` markdown block
(default) or JSON (--json) for the Stage 1/3/5 verifier panel to interpret with
fresh eyes — it is shown ONLY these raw messages, never the scope, so its
interpretation is independent.

Exit codes:
  0  success — at least one operator message recovered
  1  usage / IO error (project dir or session file missing / unreadable)
  2  parsed cleanly but recovered ZERO operator messages (caller decides — this
     is suspicious for a non-empty session and is surfaced distinctly)

Issue: hoiung/dotfiles#522 Phase 5 (verifier-led chat reconciliation).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Genuine operator prose never starts with these harness wrappers.
_SKIP_PREFIXES = (
    "<command-name>",
    "<command-message>",
    "<command-args>",
    "<local-command",
    "<bash-input>",
    "<bash-stdout>",
    "<bash-stderr>",
    "<system-reminder>",
    # Background-task completion notices: injected as type:"user" turns (isMeta
    # unset, isSidechain false) when a Workflow/Agent/Bash background job ends —
    # harness automation, never operator-typed. The single most frequent
    # user-turn wrapper class in a multi-session corpus, so omitting it leaks
    # fake "operator messages" into the verifier panel (dotfiles#522 Stage 5).
    "<task-notification>",
    "Caveat: The messages below",
    # Compaction summary injected as a user turn — harness-generated, not typed.
    "This session is being continued from a previous conversation",
)

# Skill-body injections: when the operator types `/skill`, the rendered skill
# body is sent as a user-turn text part. These open with a known H1.
_SKILL_BODY_H1 = (
    "# Leader Mode",
    "# Memory",
    "# /handover",
    "# /start",
)

_INTERRUPT_MARKER = "[Request interrupted by user]"

# A YAML frontmatter key at LINE START (anchored — not a mid-sentence `name:`).
_FRONTMATTER_KEY_RE = re.compile(r"^(name|description|metadata):", re.MULTILINE)


def _is_frontmatter_doc(stripped: str) -> bool:
    """True if `stripped` opens with a YAML frontmatter block — the signature of
    a rendered skill / memory / doc body injected as a user turn (e.g. a
    `/consultancy-ops` SKILL.md whose first line is `---`), never operator prose.

    Requires: first line exactly `---`, a closing `---` within the first 20
    lines, and a `name:` / `description:` / `metadata:` YAML key at LINE START
    in between (anchored — so an operator message like `---\nRe the name: x\n---`
    where `name:` appears mid-sentence does NOT match, and a bare `---` markdown
    rule an operator might type does NOT match).
    """
    lines = stripped.split("\n")
    if not lines or lines[0].strip() != "---":
        return False
    for i, line in enumerate(lines[1:20], start=1):
        if line.strip() == "---":
            head = "\n".join(lines[1:i])
            return bool(_FRONTMATTER_KEY_RE.search(head))
    return False


def _text_parts(content) -> list[str]:
    """Pull the text strings out of a message `content` (str or list-of-parts).

    A str content is one text. A list content yields each `type:"text"` part;
    `tool_result` (and any other) parts are dropped.
    """
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        out: list[str] = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                txt = part.get("text", "")
                if isinstance(txt, str):
                    out.append(txt)
        return out
    return []


def is_operator_text(stripped: str) -> bool:
    """True iff `stripped` (an already-.strip()'d text) is genuine operator prose.

    Centralised so the test suite reuses the exact production predicate rather
    than re-deriving a parallel filter (SST3 reuse-production-code rule).
    """
    if not stripped:
        return False
    if stripped.startswith(_SKIP_PREFIXES):
        return False
    if stripped == _INTERRUPT_MARKER:
        return False
    if stripped.startswith(_SKILL_BODY_H1):
        return False
    # The /start skill body opens with its own first line, no H1.
    if stripped.startswith("Scan the DevProjects directory"):
        return False
    # A rendered skill/doc body whose first line is YAML frontmatter (`---`).
    if _is_frontmatter_doc(stripped):
        return False
    return True


def extract_messages(records) -> list[str]:
    """Return the ordered list of genuine operator messages from parsed records.

    `records` is an iterable of decoded JSONL objects. Malformed / non-user /
    meta / sidechain records are skipped silently — the caller surfaces decode
    errors at the line level.
    """
    messages: list[str] = []
    for obj in records:
        if not isinstance(obj, dict):
            continue
        if obj.get("type") != "user":
            continue
        if obj.get("isMeta") or obj.get("isSidechain"):
            continue
        content = obj.get("message", {}).get("content") if isinstance(obj.get("message"), dict) else None
        for text in _text_parts(content):
            stripped = text.strip()
            if is_operator_text(stripped):
                messages.append(stripped)
    return messages


def _iter_records(path: Path):
    """Yield decoded JSON objects from a JSONL file, skipping blank/garbled lines."""
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                # A single corrupt line must not abort the whole transcript.
                continue


def _slug_for_cwd(cwd: Path) -> str:
    """Derive the Claude Code project-dir slug from a working directory."""
    return str(cwd.resolve()).replace("/", "-")


# A worktree project-dir slug embeds the solo branch (solo/issue-N or the
# EnterWorktree-renamed solo+issue-N) — both flatten to `solo[-+]issue-N` once the
# slug's `/`→`-` transform runs. A slug carrying this marker is unambiguous (it is
# ONE issue's worktree); a slug WITHOUT it is a bare-parent (canonical-clone) dir
# that can accumulate many issues' sessions (dotfiles#528 AC 5.3). KEEP IN SYNC with
# sst3_utils.SOLO_BRANCH_RE.
_SOLO_ISSUE_SLUG_RE = re.compile(r"solo[-+]issue-(\d+)")


def _issue_of_slug(name: str) -> int | None:
    """Issue number embedded in a worktree project-dir slug, else None."""
    m = _SOLO_ISSUE_SLUG_RE.search(name)
    return int(m.group(1)) if m else None


def resolve_sessions(args) -> list[Path]:
    """Resolve the ordered list of session JSONL files to read.

    Precedence: explicit --session > --project-dir/derived dir (+ --all-sessions).
    Within a project dir, files are returned oldest-first by mtime so the emitted
    log reads chronologically across a compaction/`/clear` boundary.
    """
    if args.session:
        p = Path(args.session)
        if not p.is_file():
            raise FileNotFoundError(f"--session file not found: {p}")
        return [p]

    issue = getattr(args, "issue", None)

    if args.project_dir:
        proj = Path(args.project_dir)
    elif issue is not None:
        # dotfiles#528 AC 5.3: --issue N selects the issue's OWN worktree project dir
        # (slug carries solo[-+]issue-N), so a bare-parent CWD slug cannot silently pick
        # another issue's session by mtime.
        base = Path(args.projects_root).expanduser()
        candidates = sorted(
            d for d in base.glob("*")
            if d.is_dir() and _issue_of_slug(d.name) == issue
        )
        if len(candidates) == 1:
            proj = candidates[0]
        elif len(candidates) > 1:
            raise ValueError(
                f"--issue {issue} matches {len(candidates)} worktree project dirs "
                f"({[c.name for c in candidates]}); pass --project-dir or --session."
            )
        else:
            # No worktree dir for issue N — fall back to the CWD slug, but VERIFY it is
            # not a different issue's worktree (fail-loud, never silently wrong).
            slug = _slug_for_cwd(Path(args.cwd) if args.cwd else Path.cwd())
            proj = base / slug
            proj_issue = _issue_of_slug(proj.name)
            if proj_issue is not None and proj_issue != issue:
                raise ValueError(
                    f"--issue {issue} but the resolved project dir '{proj.name}' is for "
                    f"issue {proj_issue}; pass --project-dir or --session."
                )
    else:
        base = Path(args.projects_root).expanduser()
        slug = _slug_for_cwd(Path(args.cwd) if args.cwd else Path.cwd())
        proj = base / slug

    if not proj.is_dir():
        raise FileNotFoundError(f"project dir not found: {proj}")

    sessions = sorted(proj.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not sessions:
        raise FileNotFoundError(f"no .jsonl session files in {proj}")
    if args.all_sessions:
        return sessions
    # dotfiles#528 AC 5.3: fail-loud on an ambiguous bare-parent slug. A non-worktree
    # project dir (slug carries no solo[-+]issue-N marker) with >1 session would otherwise
    # silently `return [sessions[-1]]` — latest-by-mtime — which can be a DIFFERENT issue's
    # session and corrupt the agreements log. Refuse; require an explicit disambiguator.
    if _issue_of_slug(proj.name) is None and len(sessions) > 1:
        raise ValueError(
            f"ambiguous: project dir '{proj.name}' is a non-worktree (bare-parent) slug "
            f"with {len(sessions)} sessions; pass --issue N, --session FILE, or "
            f"--all-sessions (refusing to silently pick latest-by-mtime — dotfiles#528 AC 5.3)."
        )
    return [sessions[-1]]  # unambiguous: a worktree slug, or a single session


def render_markdown(messages: list[str], sources: list[Path]) -> str:
    """Render the recovered messages as a `## Agreements Log` markdown block."""
    lines = ["## Agreements Log", ""]
    lines.append(f"<!-- extracted by extract-chat-agreements.py from "
                 f"{len(sources)} session(s); {len(messages)} operator message(s) -->")
    lines.append("")
    for i, msg in enumerate(messages, 1):
        # Indent continuation lines so multi-line operator messages stay inside
        # the numbered item and don't break the markdown list.
        body = msg.replace("\n", "\n   ")
        lines.append(f"{i}. {body}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Extract genuine operator-typed messages from a Claude Code session "
            "transcript for verifier-led chat reconciliation (dotfiles#522)."
        ),
    )
    parser.add_argument(
        "--session", metavar="FILE",
        help="Explicit path to a single <session>.jsonl (overrides dir discovery).",
    )
    parser.add_argument(
        "--project-dir", metavar="DIR",
        help="Claude Code project dir holding the .jsonl files "
             "(default: derived from --cwd under --projects-root).",
    )
    parser.add_argument(
        "--projects-root", metavar="DIR", default="~/.claude/projects",
        help="Root of Claude Code project dirs (default: ~/.claude/projects).",
    )
    parser.add_argument(
        "--cwd", metavar="DIR",
        help="Working directory whose slug selects the project dir "
             "(default: the actual current working directory).",
    )
    parser.add_argument(
        "--all-sessions", action="store_true",
        help="Read ALL sessions in the project dir (oldest-first), not just the "
             "latest — use when the Issue spans a compaction/`/clear` boundary.",
    )
    parser.add_argument("--issue", metavar="N", type=int, default=None,
        help="Select the worktree project dir for issue N (slug carries "
             "solo[-+]issue-N) instead of the CWD slug — disambiguates a bare-parent "
             "project dir that accumulates many issues' sessions (dotfiles#528 AC 5.3).",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit a JSON object instead of the `## Agreements Log` markdown.",
    )
    args = parser.parse_args()

    try:
        sessions = resolve_sessions(args)
    except (FileNotFoundError, ValueError) as exc:
        # ValueError = ambiguous bare-parent slug / --issue mismatch (dotfiles#528 AC 5.3).
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    messages: list[str] = []
    for sess in sessions:
        try:
            messages.extend(extract_messages(_iter_records(sess)))
        except OSError as exc:
            print(f"ERROR: cannot read {sess}: {exc}", file=sys.stderr)
            return 1

    if args.json:
        print(json.dumps({
            "sources": [str(s) for s in sessions],
            "count": len(messages),
            "messages": messages,
        }, indent=2))
    else:
        print(render_markdown(messages, sessions))

    if not messages:
        print("WARNING: recovered ZERO operator messages — check the session/dir.",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
