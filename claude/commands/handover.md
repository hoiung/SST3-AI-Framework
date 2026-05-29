# /handover — pre-compact AI-to-AI handover

Invoke this right before you compact a long session. It writes ONE structured handover that the **next** (post-compact) context will read to resume cleanly, with no information loss. The handover is **AI-to-AI**: the writer is this context, the reader is post-compact Claude — so it is terse, evidence-anchored, and optimised against drift, not written as human prose.

Optional argument: `/handover <one-line note>` — a free-text hint folded into the summary.

## Why this exists

Compaction drops the conversation and keeps only a summary. Anthropic's own compaction schema keeps **state + next-steps + learnings** and preserves the latest user turn **verbatim** — because paraphrasing the goal is where post-compact drift starts. This command writes that, plus evidence anchors, to a file the post-compact context is then commanded to re-read.

**Handovers live in `~/handover`, NOT in auto-memory.** A handover is a session-scoped resume aid — relevant only until the work it describes is resumed, then eligible for auto-cleanup. It lives in `~/handover` (a WSL-native `$HOME` directory, outside every git repo so it is never synced to GitHub) precisely because that survives **both** a compaction **and** a full WSL VM restart / idle-reap — unlike `/tmp`, which a VM teardown wipes (the one event a handover most needs to outlive). The `SessionStart` compact hook re-injects `~/handover/current-task.txt`, which points the post-compact context at the handover file. That closes the loop without writing anything to permanent memory.

**Do NOT write the handover to the auto-memory directory or add a `MEMORY.md` index bullet.** That was the old behaviour and it caused unbounded accumulation — every session's handover piling into permanent memory forever, bloating the auto-loaded index for no resume value. Auto-memory is for *durable* facts (user/feedback/project/reference). A per-session resume snapshot is not durable — it belongs in `~/handover`. If this session produced a durable lesson, capture THAT as a normal `feedback_*` / `project_*` memory, separately — not as a handover.

**Three-tier state model**: durable facts → auto-memory; session-resume snapshot (survives reboot, auto-pruned after 7 days) → `~/handover`; throwaway scratch with no resume value → `/tmp`. `~/handover` is self-cleaning: a daily `systemd-tmpfiles` rule prunes anything older than 7 days, so old handovers do not accumulate and `$HOME` stays tidy. (A file that is read during resume has its access time bumped, so an in-use handover is not pruned mid-flight.)

## What to do when invoked (in order)

**Step 1 — Write the handover file to `~/handover`.**
Write a new file `~/handover/handover_<repo-or-topic-slug>_<YYYY-MM-DD>.md`. For Issue-tied work, put the issue number in the slug (e.g. `handover_<repo>-<issue>-<topic>_<date>.md`). Optional light frontmatter (`name` / `description`) is fine for readability, but this is a `~/handover` working file, NOT a memory file — do not give it `metadata.node_type: memory`. (`~/handover` is created by the per-machine install; if it is somehow absent, the Write tool creates the parent directory anyway.)

The body uses these **8 field labels VERBATIM** (this is the authoring contract — do not rename, do not drop):

1. `GOAL (verbatim)` — the operator's goal quoted word-for-word. Do NOT paraphrase. This is the single most important field; paraphrasing it is the #1 source of post-compact drift.
2. `STATE` — what is DONE vs IN-PROGRESS, each line carrying an evidence anchor (commit SHA / test count / file:line). Not "auth is mostly done" — "auth login flow done (commit a1b2c3d, 7/7 tests pass); refresh-token path IN-PROGRESS (src/auth.py:88)".
3. `NEXT ACTION` — the single concrete next step the reader should take first. One step, not a backlog.
4. `ANCHORS` — the real file:line / artifact paths the reader must re-open to continue. Pointers to source, so the reader verifies rather than trusts the summary.
5. `DECISIONS` — decisions already made, each with its rationale AND what was RULED OUT (so the reader does not re-litigate or undo them).
6. `CONSTRAINTS` — hard rules in force this session ("don't touch X", required format, branch safety) that would otherwise be lost with the conversation.
7. `OPEN` — open questions / blockers genuinely undecided (so the reader knows what is settled vs not).
8. `LEARNINGS` — gotchas discovered this session (e.g. "endpoint is side-effecting — use --head", "test harness needs RTH ticks"). Cheap to record, expensive to rediscover.

**Step 2 — Update the compact-hook task file (deterministic re-surface).**
Write to `~/handover/current-task.txt` (the file the `SessionStart` compact hook reads and re-injects after a compact) the verbatim current task PLUS an explicit imperative — NOT a bare path — so the post-compact context is commanded to open the handover:

```text
<verbatim operator goal>
Post-compact: READ ~/handover/handover_<slug>_<date>.md IN FULL before resuming — it holds the goal/state/next-action.
```

The hook re-surfaces this text and a fixed "re-read CLAUDE.md/STANDARDS/ANTI-PATTERNS/WORKFLOW/Issue" directive, but it does NOT itself read the handover body — so the imperative above is what closes the loop. (The hook resolves `~/handover/current-task.txt` by default; `/handover` always writes the pointer there, so the hook never needs to read anywhere else.)

(If another live session may also be compacting, note that `~/handover/current-task.txt` is a single shared file — overwriting it points the hook at THIS session's handover. That is correct for the session being compacted now; just be aware it is not per-session.)

**Step 3 — Report and confirm.**
Tell the operator: the `~/handover` handover file path, the task-file line you wrote, and a one-line "safe to compact now". Then stop — let the operator trigger the compact.

## Anti-patterns — do NOT do these

- **Do NOT write to auto-memory / `MEMORY.md`.** Handovers are session-scoped `~/handover` files. Writing them to memory bloats the auto-loaded index permanently — the exact failure this skill was rewritten to stop.
- **No prose-narrative summary.** A paragraph retelling the session strips the reasoning chain and is unverifiable. Use the 8 structured fields.
- **Not a raw-history dump.** Dumping everything adds noise and buries the signal (lost-in-the-middle). Write the high-leverage fields only.
- **Do not paraphrase the operator goal.** Quote it verbatim in field 1 — paraphrase is where drift begins.
- **Never drop the file:line anchors.** Anchors let the reader re-read source instead of trusting a summary; dropping them is the direct cause of post-compact hallucination.

## Relationship to the Issue-comment handover

For Issue-tied SST3 work, the canonical session checkpoint still goes to the GitHub Issue comment per `templates/chat-handover.md`. `/handover` complements that — it is the `~/handover` resume snapshot for any pre-compact moment (Issue or not). Use both when on an active Issue; the Issue comment is the durable record, the `~/handover` handover is the same-session resume aid.
