# Root cause — brief findings 2 and 3

Settled by transcript archaeology over the reporting session (`prohibitions`
project, session `b078a574`, its subagent `aindex-arbiter-d2ea4d3968dbb5d1`) and
the `ddaanet` tier's own git history. All timestamps UTC, as recorded in the
JSONL.

## Finding 2 — not reproducible; the brief's mechanism is disproved

The brief's instance is `markdown-formatter-choice.md`. In the tier's history
that file has **never** carried `node_type`, `originSessionId` or `modified`:
`git log -S originSessionId -- markdown-formatter-choice.md` is empty, and the
file today still reads `metadata:` / `  type: reference`. It is one of only two
files in the tier (with `shared-claude.md`) that lack the fields; the other 87
carry them **from their creating commit**.

`originSessionId` was not overwritten on any of the 13 reconciled files. The
editing session was `b078a574`; every one of the 13 still names a different,
older session — `design-doc-no-situational-state.md` keeps `a0cb79ca` (its
2026-09-02 12:39 creator), `sessionstart-resume-cwd.md` keeps `8ce39f20`, and so
on.

What *is* real is a `modified:` restamp, and it is the harness's, not gitlore's.
Each file the subagent edited with the **Edit tool** has `modified:` 150–300 ms
after that call:

| file | Edit call | `modified:` |
|---|---|---|
| `bash-tool-set-e-inert.md` | 22:12:10.496 | 22:12:10.638 |
| `design-doc-no-situational-state.md` | 22:12:15.611 | 22:12:15.776 |
| `jsonl-reader-type-guard.md` | 22:12:40.174 | 22:12:40.323 |
| `git-subtree-ensure-clean-unscoped.md` | 22:12:57.458 | 22:12:57.727 |

The two files whose `description:` was written by a **Bash** heredoc instead
(`cc-async-task-notification-quirks.md`,
`subagent-skips-at-import-expansion.md`, at 22:13:58) were **not** restamped —
they still carry their August `modified:` values. Tool-call-keyed restamping of
a memory file is Claude Code's own auto-memory maintenance; gitlore's setter
(`gitlore_set_frontmatter_description`) rewrites the first `description:` line
and passes every other line through.

The brief also mis-attributes the writer: gitlore's sync hook did not set these
descriptions at all. The subagent edited the 13 fact files directly
(22:12:10–22:12:57), one `Edit` each.

**Disposition:** no gitlore defect. `modified:` restamping on Edit is correct
and the brief agrees it is fine. Nothing invents provenance.

## Finding 3 — real, but not the stated mechanism

Composition **did** run on the subagent's index edit, inside the subagent, and
its report reached nobody. The parent then reverted the composition output as if
it were a hand edit.

Timeline:

| time | who | event |
|---|---|---|
| 22:10:47.696 | SUB | `Edit` on `memory/MEMORY.md` (first amended line) |
| 22:10:47.939 | MAIN | `Bash` (`git -C memory status --short; …`) — batch in flight |
| ≤22:10:50.9 | — | carrier `memory/ddaanet/MEMORY.md` is dirty in that command's own output |
| 22:10:57.509 | MAIN | `git -C memory diff`; carrier confirmed modified |
| 22:11:17.320 | SUB | `Edit` on `memory/MEMORY.md` (second amended line) |
| 22:11:28.494 | MAIN | `git -C memory/ddaanet checkout -- MEMORY.md` — **reverts the carrier** |

The carrier was dirty *inside the result of the parent's in-flight command*,
about 3 s after the subagent's edit and before the parent's own `PostToolBatch`
could have fired. So `PostToolBatch` fires inside a subagent and gitlore's
compose ran there — consistent with `agent_id` being present in hook stdin only
when the hook fires from within a subagent.

The report was dropped on both sides. `gitlore: recomposed tier pointers`
appears 5 times in the main transcript for this session — at 06:08:50, and as
paired `attachment` entries at 16:32:46 and 16:34:41, both following a
**parent-side** `Edit` on `memory/MEMORY.md` — and **zero times** in the
22:10–22:15 window. The subagent transcript carries 5 `attachment` entries, all
`deferred_tools_delta` / `sandbox_instructions` / `skill_listing`: no hook
output at all. So neither the subagent's own context nor the parent's received
the "this is expected and complete — do not re-read or re-edit them to verify"
message that exists precisely to prevent the revert that followed.

**The race is real but was not the failure here.** `index-sync-pre.sh` writes
two fixed paths in the memory gitdir (`gitlore-index-preimage`,
`gitlore-compose-stamp`), shared by parent and subagent with no per-agent
keying, and every `PostToolBatch` consumer `rm -f`s them unconditionally. At
22:10:47 the parent's Bash pre-hook found both already present (written 243 ms
earlier by the subagent's Edit) and left them; the subagent's post-batch then
consumed and deleted them, so the parent's post-batch found no baseline and
exited silently. Here that was harmless — compose had already run. The harmful
ordering is the mirror: a parent batch ending between a subagent's pre-hook and
its post-hook consumes the subagent's baseline, and the subagent's edit then
propagates to nothing, silently.

**Two defects, not one:**

1. A subagent-side `PostToolBatch` report is delivered to no one, so a correct
   composition looks like unexplained dirt to the parent. Reported as
   "propagates to nothing" because the only visible evidence was a dirty carrier
   the parent then destroyed.
2. The pre-image and compose-stamp paths are not keyed by agent, so parent and
   subagent batches can consume each other's baselines.

Finding 1's false sentence is what turned defect 1 into the revert: the parent
believed composition structurally could not re-text a carrier line, so a
re-texted carrier read as a hand edit.
