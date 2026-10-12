# A dying `PostToolBatch` hook reports instead of ending the turn

2026-10-12. A batch hook that dies says so to the user and the agent and exits
0; it never exits 2, and it never dies on a baseline another copy consumed.

## Why

Measured on CC 2.1.296 with a scratch `PostToolBatch` hook under `claude -p`
(`plans/batch-hook-deaths/probe/run.sh <code>` reruns a row, unsandboxed):

| Hook exit              | Turn   | Agent sees                 | Transcript                        |
| ---------------------- | ------ | -------------------------- | --------------------------------- |
| 0 + `additionalContext` | goes on | the context                | `hook_additional_context`         |
| 1 or 3                 | goes on | nothing                    | `hook_non_blocking_error`, stderr |
| 2                      | ends, empty reply | the stderr, next user turn | `hook_stopped_continuation` |

`awk`, `cmp` and `grep` exit 2 on a file they cannot open, so under `set -e`
`index-sync-post.sh` dies with 2 when its stash vanishes between `[ -f ]` and
`gitlore_index_pairs` — the silent turn. Every other death is exit 1-ish: the
user gets a notice, the agent nothing, and inside a subagent (D51) nobody does.
`docs/references/index-authoring-sync.md` states the opposite on both counts
(exit 2 blocks "only at `PreToolUse`"; non-zero is "less visible").

Not measured: how many stderr lines the interactive TUI renders; on bash 3.2,
`exit` inside an `EXIT` trap, `exec 2>` restore, and an `ERR` trap under
`set -E` handing `$BASH_COMMAND` and `$LINENO` to the `EXIT` trap (T1 pins all
three).

## Decision to record

Lands in `docs/decisions.md` and `index-authoring-sync.md` (T5) when the code is
true.

- **D60 — A `PostToolBatch` hook that dies reports on both channels and exits 0;
  when it cannot report, it exits non-zero but never 2.** A shared guard
  captures the hook's stderr and, on a non-zero death, emits one JSON object:
  `systemMessage` with hook name, status, the failing command and its line, and
  the captured error; `additionalContext` with the same plus the hook's own
  statement of what did not happen. If the capture file or the `jq` encode
  fails, it replays the stderr and exits with the original status, 2 remapped to 1. *Rejected:* exit 1 passthrough alone — the agent learns nothing, and in a
  subagent no one does; a fixed message with no capture — discards the failing
  tool's own error; per-site `|| exit 0` — already rejected as a dishonest error
  path; a wrapper script in `hooks.json` — six extra spawns per batch in every
  repo; rewriting every non-zero status to 1 — loses the status for nothing.

## Interfaces

```bash
# scripts/lib/hook-guard.sh, sourced through util.sh.
# $1 = hook name; $2 = memory worktree path; $3 = consequence sentence, agent-facing.
# Call once, after mempath resolves and before the first fallible step that
# follows it. Sets GITLORE_HOOK_OWNED="" — a newline-joined list of files the
# trap removes on any exit; append a claimed baseline to it.
gitlore_batch_hook_guard() { … }
```

Invariants: no file is created in a repo without the memory submodule (the six
hooks exit before the call there); stderr the hook writes on a clean exit still
reaches the real stderr; the guard writes stdout only on a death, and all six
hooks write theirs as their last act, so one object is emitted either way — a
`jq` dying mid-emit is the stated residual. Deaths before the call (sourcing,
`cd`) stay plain non-zero exits; none of them is an exit-2 path. A hook killed
by a signal runs no trap: it strands its capture file and any claimed baseline,
one file per kill and never reused, since every reader tests the unclaimed name.

## Tasks

Each: red (an assertion naming the state of the world), green, the suite named.
Dispatch per the task frame: Sonnet writes reds and prose, a different agent
reviews each red, Haiku does green, one agent at a time, unnamed, each with an
output file. The three agents are reused across T1–T5 by `SendMessage` and
respawned only past ~150k tokens of context; this plan has no internal seam.
`just precommit` in the background before each commit.

**T1 — The guard.** `scripts/lib/hook-guard.sh` and `tests/hook_guard.bats`,
driven through a fixture hook script run as `bash script`, never a sourced
function. Postconditions: a death with status 1, 2 and 5 each exits 0 with one
JSON object whose `systemMessage` and `additionalContext` both carry the hook
name, the status and the dying command's stderr text; a death from a command
that writes no stderr (`cmp -s`, a bare `[ … ]`) still reports that command's
text and line, inside a function as well as at top level; the consequence
sentence is in `additionalContext` only; an unwritable capture directory yields
the original status on exit (1 for 2) with the stderr replayed; a broken `jq` on
`PATH` yields the same; a clean exit leaves stdout untouched, replays stderr,
and leaves no capture file; a file named in `GITLORE_HOOK_OWNED` is gone after
both a clean exit and a death. Lock-ins for the three bash 3.2 unknowns go in
`tests/bsd_portability.bats`.

**T2 — The six hooks call it.** One call each in `index-sync-post.sh`,
`index-compose.sh`, `add-tier-batch.sh`, `memory-commit-batch.sh`,
`plugin-upgrade-batch.sh`, `relay-drain.sh`, each with its own consequence
sentence (sync: frontmatter not synced this batch; compose: indexes not
recomposed; add-tier: mount outcome unknown, check `.gitmodules`; commit: commit
outcome unknown, both IPC files as found; upgrade: an empty `$3`, since nothing
depends on the notice; drain: relayed reports stay staged). Red per hook in its
existing suite: a forced death — an unreadable stash for the sync, the cheapest
equivalent for the others — exits 0 with the report.
`tests/plugin_distribution.bats` asserts every script registered under
`PostToolBatch` in `hooks/hooks.json` contains the call, so a seventh hook
cannot ship without it.

**T3 — Baselines are claimed by rename.** `index-sync-post.sh` and
`index-compose.sh` `mv` their baseline to `<name>.$$` before reading it and
append the claimed name to `GITLORE_HOOK_OWNED`; a failed `mv` on a file that is
no longer there is a quiet `exit 0`. Postconditions, for the stash and the stamp
alike: (a) baseline absent → exit 0, empty stdout, empty stderr; (b) baseline
present → one propagation or compose, and `<name>.$$` gone afterwards; (c)
baseline present and a forced death after the claim → the T1 report, and
`<name>.$$` gone. Two racing copies, and `add-tier-batch.sh` removing the stamp
mid-run, are (a) and (b) together and get no test of their own.
`index-sync-pre.sh` is unchanged — it tests the unclaimed name only.

**T4 — Point fixes.** `add-tier-batch.sh`: `gitlore_compose_and_report` under
`if !`, so a failed recompose after a successful mount still emits the mount
report with a line saying composition did not run. `plugin-upgrade-batch.sh`:
`|| session=""` on the payload parse, and the notice withheld when the marker
`touch` fails is not — it goes out and repeats, as `index-compose.sh` already
does for its own marker. One red each.

**T5 — Docs.** `index-authoring-sync.md` lines 77–91 state the measured table
and the guard. Scope of the correction: two clauses are wrong — exit 2 blocking
"only at `PreToolUse`", and a non-zero exit being "less visible". The rule that
neither hook may `exit 2` stands, and for `index-sync-pre.sh` so does its
reason: it is `PreToolUse`, where exit 2 blocks the write. Then D60 into
`docs/decisions.md`; `docs/design.md` Architecture gains one sentence naming the
guard; a changelog entry. `craft:design-doc-writing` loaded first.

## Not in this slice

- `PreToolUse` hooks (`index-sync-pre.sh`, `edit-weld-pre.sh`), where exit 2
  blocks the tool call: unaudited, and the guard's exit-0 report is the wrong
  default where a hook may need to fail closed.
- A line-by-line audit of the compose library for exit-2 paths: the guard makes
  each one a report, which is what locates it.
- Relaying a subagent's death report to the parent through `relay-drain.sh`: the
  subagent gets it on `additionalContext`; staging it from a trap in a failing
  environment waits for evidence it is needed.

## Follow-up outside this repo

`plugin-craft:hook-authoring` routes exit 2 per event and says nothing of
`PostToolBatch` ending the turn or of the agent seeing nothing on exit 1. A
brief carrying the table above and the CC version goes to that repo once D60
lands; that repo is read-only from here.
