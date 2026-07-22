#!/usr/bin/env python3
"""Backup issue bodies before Issue Assignment rollout.
[#406 Phase 9 — MANUAL UTILITY] Not wired into .pre-commit-config.yaml or CI by design. Invoke directly when needed (manual workflow tool, not a per-commit hook).


This script creates a JSON snapshot of all open issue bodies across specified
repos. Used as a safety net before running rollout-issue-assignment.py.

Exit codes:
    0: Backup successful
    3: Error (gh CLI not found, file write error, repo not found)
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from sst3_utils import fix_windows_console, KNOWN_REPOS

fix_windows_console()


# Build REPOS path dict from sst3_utils.KNOWN_REPOS — single source of truth.
# dotfiles is special-cased (its scripts are inside SST3/scripts so the path
# resolution differs from sibling repos).
#
# #500 Stage 5 worktree-CWD fix: when invoked from .claude/worktrees/<wt>/,
# Path(__file__).parent.parent.parent resolved to the worktree root, then
# .parent landed in .claude/worktrees/ (not ~/DevProjects/), and every
# consumer-repo lookup silently missed. Use sst3_mirror_utils.resolve_main_clone_root
# (the env-immune helper propagate-template.py adopted post-#488) so the
# DevProjects base is canonical regardless of worktree state.
_SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPT_DIR))
import sst3_mirror_utils as _smu  # noqa: E402
# dotfiles#552 AC 3.2 — `_SCRIPT_DIR.parent / MANIFEST_FILENAME` is only the FIRST
# of the candidates `find_manifest()` already knows about, and it is the one that
# assumes the NESTED canonical layout. In the FLATTENED public mirror it points at
# a manifest that is deliberately never published, and the sibling-dotfiles
# candidate -- the documented resolution for consumers and mirrors -- was never
# reached. Reuse the full resolver rather than re-implementing one branch of it.
_MANIFEST_PATH = _smu.find_manifest(_SCRIPT_DIR)
_DOTFILES_ROOT = _smu.resolve_main_clone_root(_MANIFEST_PATH)
_DEVPROJECTS = _DOTFILES_ROOT.parent
REPOS = {
    name: (_DOTFILES_ROOT if name == 'dotfiles' else _DEVPROJECTS / name)
    for name in KNOWN_REPOS
}


def fetch_open_issues(repo_path: Path) -> list[dict]:
    """Fetch all open issues for a repository.

    Args:
        repo_path: Path to repository directory

    Returns:
        List of issue dicts with number, title, body, labels

    Raises:
        subprocess.CalledProcessError: If gh CLI fails
    """
    result = subprocess.run(
        ['gh', 'issue', 'list', '--state', 'open', '--json', 'number,title,body,labels', '--limit', '1000'],
        cwd=repo_path,
        capture_output=True,
        text=True,
        encoding='utf-8',
        timeout=60,
        check=True
    )
    return json.loads(result.stdout)


def filter_non_epic_issues(issues: list[dict]) -> list[dict]:
    """Filter out issues with 'epic' label.

    Args:
        issues: List of issue dicts

    Returns:
        Filtered list excluding epic issues
    """
    return [
        issue for issue in issues
        if not any(label.get('name') == 'epic' for label in issue.get('labels', []))
    ]


def backup_issues(repos: list[str], output_path: str) -> dict:
    """Backup issue bodies from specified repositories.

    Args:
        repos: List of repository names ('dotfiles', '<consumer-public-1>', etc.)
        output_path: Path to output JSON file

    Returns:
        Backup data dictionary

    Raises:
        FileNotFoundError: If repository path doesn't exist
        subprocess.CalledProcessError: If gh CLI fails
    """
    backups = {}
    total_issues = 0

    for repo_name in repos:
        if repo_name not in REPOS:
            print(f"Error: Unknown repo '{repo_name}'", file=sys.stderr)
            sys.exit(3)

        repo_path = REPOS[repo_name]
        if not repo_path.exists():
            print(f"Error: Repository path not found: {repo_path}", file=sys.stderr)
            sys.exit(3)

        print(f"Fetching issues from {repo_name}...")
        all_issues = fetch_open_issues(repo_path)
        filtered_issues = filter_non_epic_issues(all_issues)

        backups[repo_name] = [
            {
                'number': issue['number'],
                'title': issue['title'],
                'body': issue['body'],
                'labels': [label['name'] for label in issue.get('labels', [])],
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
            for issue in filtered_issues
        ]

        total_issues += len(backups[repo_name])
        print(f"  ✓ Backed up {len(backups[repo_name])} issues (excluded {len(all_issues) - len(backups[repo_name])} epic issues)")

    result = {
        'metadata': {
            'created_at': datetime.now(timezone.utc).isoformat(),
            'repos': repos,
            'total_issues': total_issues
        },
        'backups': backups
    }

    # Atomic write backup file
    output = Path(output_path)
    tmp = output.with_suffix('.tmp')
    tmp.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    tmp.replace(output)
    print(f"\n✓ Backup saved to: {output_path}")
    print(f"  Total issues backed up: {total_issues}")

    return result


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Backup issue bodies before Stage Assignment rollout',
        epilog='''
Examples:
  # Backup dotfiles issues
  python backup-issue-bodies.py --repos dotfiles --output backup-dotfiles.json

  # Backup all repos
  python backup-issue-bodies.py --repos all --output backup-20251128.json

  # Backup specific repos
  python backup-issue-bodies.py --repos dotfiles,<consumer-public-1> --output backup.json
        ''',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--repos',
        required=True,
        help='Repositories to backup (dotfiles, <consumer-public-1>, <consumer-public-2>, or "all")'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Output JSON file path (e.g., backup-20251128.json)'
    )

    args = parser.parse_args()

    # Parse repos argument
    if args.repos == 'all':
        repos = list(REPOS.keys())
    else:
        repos = [r.strip() for r in args.repos.split(',')]

    # Check for gh CLI
    try:
        subprocess.run(['gh', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: GitHub CLI (gh) not found or not working", file=sys.stderr)
        sys.exit(3)

    try:
        backup_issues(repos, args.output)
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(3)


if __name__ == '__main__':
    main()
