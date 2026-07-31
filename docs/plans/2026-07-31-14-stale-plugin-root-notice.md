# A mid-session plugin upgrade is a notice, not a self-healing config

## What the probe settled

Two `-p` runs of a throwaway `--plugin-dir` plugin whose `SessionStart` hook logs
its root, the payload's `source`, and the session id; `hooks.json` was rewritten
between them to point at a *different* script:

| | run 1 — `claude -p` | run 2 — `claude -c -p` |
|---|---|---|
| SessionStart | fired, `source=startup` | fired, **`source=resume`** |
| hook that ran | `hook1.sh` | **`hook2.sh`** — registered after run 1 |
| session id | `42bb22be…` | same |

Hook *event registration* is per process, not per conversation. The session
transcript records no plugin path or version anywhere (`grep` for the plugin
root: no hits), so a resumed process has no stale root to restore — it re-resolves
`CLAUDE_PLUGIN_ROOT` from `~/.claude/plugins/installed_plugins.json` at startup,
and gitlore's `SessionStart` then re-pins the five `gitlore.*` keys, re-emits the
wrappers and re-wires the memory gate exactly as a cold start does.

**Exit and relaunch with `claude -c` is the entire remedy, and it keeps the
conversation.** Nothing inside a live session can substitute for it.

## What that kills

The brief's first two directions both try to make a *live* session pick the
upgrade up, and both are unreachable:

- **Version-less pointer resolved at hook runtime.** It would repoint the git
  hooks at the new version while CC-side hook registration, skill bodies and
  agent definitions stayed on the old one — a split-version session, strictly
  worse than uniform staleness. It is also factually wrong about the cache:
  installs are pinned per scope, not globally (`~/code/home` at `0.4.3`,
  `~/code/gitmoji` at `0.3.0`, with `0.4.4` sitting in the same cache), so
  "newest cached" is not "installed here".
- **Wrappers self-heal from `CLAUDE_PLUGIN_ROOT`.** That variable is exported
  to CC hooks only. A git hook fires from agent Bash, where it is unset, so the
  wrapper has nothing to heal from — and the split-version objection stands.

The third direction — make the failure self-describing — is the whole fix, and
it splits in two: gitlore only ever *writes* the five keys
(`scripts/cc-hooks/session-start.sh:85-89`,
`scripts/install/write-settings.sh:40`), so the misleading diagnosis the brief
quotes belongs to `handoff-checkpoint`. gitlore's own contribution is to notice
the upgrade and name the remedy while the session is still running.

## The detector

New `PostToolBatch` hook, `scripts/cc-hooks/plugin-upgrade-batch.sh`. It compares
the root this session froze at against what the install record says is installed
here, and fires once per session.

```
record        = ${GITLORE_PLUGIN_RECORD:-$HOME/.claude/plugins/installed_plugins.json}
cache_prefix  = $(dirname "$record")/cache/
```

One override covers both paths, so the suite drives it under a temp `HOME`
without a second knob.

Guards, in order, each an `exit 0`:

1. `CLAUDE_PLUGIN_ROOT` unset.
2. `gitlore_cd_project_root` / `gitlore_has_submodule` fail — the keys only exist
   in a gitlore repo.
3. `$CLAUDE_PLUGIN_ROOT` is not under `cache_prefix`. A `--plugin-dir` checkout
   is never stale, and without this guard development sessions — including this
   repo's own, whose `gitlore.hooksDir` is `/Users/david/code/gitlore/scripts/
   git-hooks` — would warn every batch.
4. `record` missing or unparseable.
5. This session's marker already exists.

Then, owner-agnostic (no `gitlore@ddaanet` literal — the parent dir of the frozen
root *is* the plugin's cache family):

```sh
parent=$(dirname "$CLAUDE_PLUGIN_ROOT")     # …/cache/<owner>/gitlore
jq -r --arg proj "$PWD" --arg parent "$parent/" '
  .plugins // {} | to_entries[] | .value[]
  | select(.scope == "user" or .projectPath == $proj)
  | select(.installPath | startswith($parent))
  | [.scope, .version, .installPath] | @tsv' "$record"
```

Fire only when that set is non-empty and contains no entry whose `installPath`
equals the frozen root. A repo pinned to an older project-scoped version than the
user-scoped one is therefore silent — the frozen root matches an entry, which is
the point. Name the project-scoped entry when there is one, else the user-scoped
one; the remedy does not depend on which.

No `grep -F` short-circuit before the `jq`: the frozen root can appear in the
record under a *different* `projectPath`, so a bare match is a false negative.
The `jq` costs less than the hook's own process spawn.

Marker: `gitlore_upgrade_nudge_file "$mempath" "$session"` in the memory store's
gitdir, mirroring `gitlore_index_budget_nudge_file`
(`scripts/lib/index-sync.sh:147-165`) — same naming, same 7-day sweep, cleared by
`recall-reset.sh` at `SessionStart` and `PreCompact`, so a compaction re-arms it.

Wording, both channels (D14 — `systemMessage` is user-only, so the agent needs
its own line):

> **systemMessage** — gitlore: this session runs `<old>`, but `<new>` is what is
> installed for this repo. A mid-session upgrade does not take effect: hook
> registration, skill bodies and the five `gitlore.*` git-config keys are all
> fixed at process start. Exit Claude and relaunch with `claude -c` — it resumes
> this conversation.

> **additionalContext** — gitlore: the plugin was upgraded to `<new>` since this
> session started; this session still runs `<old>` and its git-config keys point
> into `<old>`. Nothing in this session can adopt it. Do not attempt a repair
> with `/plugin`, `/reload-plugins`, or by rewriting `gitlore.*` git config — none
> of them re-fire `SessionStart`. Tell the user to exit and relaunch with
> `claude -c`.

The prohibition is the load-bearing half of the agent line: the observed session
ran two full cycles of exactly those remedies.

## Steps

1. **Red.** `tests/cc_hook_plugin_upgrade.bats`, trigger strings held in
   test-side globals so every negative is paired with a positive over the same
   fixture: fires when the record names a different `installPath` for this
   project; silent when the frozen root is the recorded one; silent when the
   frozen root is outside `cache_prefix` *while the record still names a
   different path*; silent on a second batch, and firing again once the marker
   is cleared; silent outside a gitlore repo. Plus: the hook never fails a batch
   (malformed record → exit 0, no output).
2. **Green.** `gitlore_upgrade_nudge_file` + its reset in
   `scripts/lib/index-sync.sh`, the reset call in `scripts/cc-hooks/recall-reset.sh`,
   and `scripts/cc-hooks/plugin-upgrade-batch.sh`.
3. **Invocation path.** Register the hook in `hooks/hooks.json` under
   `PostToolBatch`; assert registration *and* `[ -x ]` in
   `tests/plugin_distribution.bats`, alongside the existing
   `memory-commit-batch` assertion (`:129-138`). Ordering against the other five
   batch hooks is free — this one reads no state they write.
4. **Docs.** `docs/design.md`: **D21** for the notice and its reasoning (the
   five keys self-heal on *any* process start including `resume`; staleness is
   reported, never routed around), one Components entry for the hook, and a
   Rejected Alternatives pair for runtime version resolution and wrapper
   self-heal, each with the split-version argument. Extend **D5**'s staleness
   window to name `claude -c` as the refresh. `docs/changelog.md` gets the dated
   entry.
5. **Memory.** Update `ddaanet/reference_stale_plugin_code`: `claude -c` is a
   full process restart — `SessionStart` fires with `source=resume`, `hooks.json`
   is re-read, plugin roots are re-resolved from `installed_plugins.json`, and the
   conversation survives — so the standing "start a new session" advice becomes
   "exit and `claude -c`". Add the per-scope pinning fact. Retarget its index
   line's trailing `— restart` in `memory/MEMORY.md` without lengthening it (the
   index is at ~23.3KB against the 24.4KB loader cutoff).
6. **handoff.** Move `brief-stale-config-after-mid-session-upgrade.md` into
   `~/code/handoff/`, with the probe result and replacement wording for
   `handoff-checkpoint`'s three-way diagnosis (not installed here / key unset /
   key points at a vanished path) appended. handoff's code stays untouched.

## Not in this plan

The detector only reaches other repos once a release lands and each repo runs
`/plugin update` — the pending version-bump strand covers that, and it is
independent of the work above.
