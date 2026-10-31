# The plugin-upgrade notice — decision D21

A plugin upgraded mid-session leaves the running session on the old version.
This node holds the argument for reporting that and never repairing it; the
`SessionStart` wiring it sits beside is in [session.md](session.md).

- Plugin upgrade — **D21** a mid-session plugin upgrade is a notice, not a
  self-healing config

---

## Decisions — D21

**D21 — A mid-session plugin upgrade is a notice, not a self-healing config**

`CLAUDE_PLUGIN_ROOT` is resolved once, at process start, from
`~/.claude/plugins/installed_plugins.json`. That record keeps moving while a
session runs: another repo's session installs, or the user runs
`/plugin update`. Everything this session froze at start then belongs to the
*old* version — hook event registration, skill bodies, agent definitions, and
the `gitlore.hooksDir` key that points into the plugin root (D5 in
[hook-wrappers.md](hook-wrappers.md)). The `PostToolBatch` hook
`plugin-upgrade-batch.sh` notices the disagreement and names the remedy, once
per episode.

**Everything frozen at process start is re-read on a resume, so `claude -c` is
the entire remedy.** Verified 2026-07-31 by a two-run `--plugin-dir` probe whose
`SessionStart` hook logged its root and the payload's `source`, with
`hooks.json` rewritten between runs: the second run fired `SessionStart` with
`source=resume` and ran the **new** command, under the **same** `session_id`.
The transcript records no plugin path or version, so a resumed process has no
stale root to restore — it re-resolves the root from the install record, re-pins
the key, and re-emits the wrappers exactly as a cold start does, and the
conversation survives. Nothing available inside a live session substitutes for
it.

**Why reporting is the whole fix.** Both ways of making a live session adopt the
upgrade produce a *split-version* session, strictly worse than uniform
staleness: the git-config keys would point into the new version while CC-side
hook registration, skill bodies and agent definitions stayed on the old one.
Uniform staleness has one failure mode and one remedy; a split has neither.

**Detection.** The hook compares the frozen root against the entries the record
holds for this plugin — the user-scoped one, plus any entry pinned to this
project — and fires only when that set is non-empty and holds no entry equal to
the frozen root. A repo deliberately pinned behind the user-scoped version is
therefore silent, which is the point: installs are pinned per scope, not
globally, and repos routinely sit at different versions. The family is
identified by the frozen root's parent directory rather than a `gitlore@ddaanet`
literal, so a fork or a renamed marketplace works unchanged. Three guards
precede it: no `CLAUDE_PLUGIN_ROOT`, no memory submodule, and a frozen root
outside the plugin cache — the last because a `--plugin-dir` checkout is never
stale, and its parent is an ordinary source directory whose neighbours the
record may name for some *other* locally-installed plugin. There is no `grep -F`
short-circuit ahead of the record query: the frozen root can appear in the
record under a different `projectPath`, where a bare match would read as
"installed here" and suppress a real notice.

**Both channels, and the user-facing one carries the instruction.** D14's house
style keeps `systemMessage` curt and free of actionable phrases, leaving
remedies to `additionalContext`. This is the deliberate exception, on D7
grounds: only the user can exit and relaunch, and a hot-path notice routed
through the agent is model-dependent. So the user's line names the remedy
directly. The agent's line is mostly a prohibition — `/plugin`,
`/reload-plugins` and rewriting the `gitlore.*` keys are all dead ends, none of
them re-fires `SessionStart`.

**Once per episode, re-armed by a fresh or condensed context.** A marker in the
memory store's gitdir, keyed by session and swept after seven days, mirrors the
index byte-budget nudge; `nudge-reset.sh` clears both at
`SessionStart(startup|clear|compact)`. `startup` and `clear` begin a fresh
context; `compact` leaves a summary that may have dropped the notice, while the
session is still running the old root. `resume` and `fork` keep the conversation
history, so the notice the session was given is still in its context and the
marker stays. A compaction is always followed by `SessionStart` with
`source: "compact"`. The source filter is the matcher of the script's own
`hooks.json` group, a list of exact alternatives matched against `source`:
mechanical branching belongs in the harness, and the script never runs on
`resume`, the one event where `SessionStart`'s cwd can be a foreign repo.

## Rejected alternatives

**A version-less plugin pointer, resolved at hook runtime.** Pointing the five
`gitlore.*` keys at a symlink refreshed per lookup would let git-side hooks
follow an upgrade mid-session while CC-side hook registration, skill bodies and
agent definitions stayed on the version the process froze at — a split-version
session, worse than uniform staleness, which has one failure mode and one remedy
(D21). The premise is also wrong: installs are pinned per scope and per project,
not globally, so "the newest directory in the cache" is not what a given repo
loads.

**Wrappers self-healing from `CLAUDE_PLUGIN_ROOT`.** That variable is exported
to Claude Code hooks only. A git hook fires from agent Bash, where it is unset,
so the wrapper has nothing to heal from — and the split-version objection above
stands regardless (D21).

**A `PreCompact` registration of the nudge reset.** `SessionStart(compact)`
follows every compaction, so a second registration re-arms nothing the first has
not (D21).

**Re-arming on every `SessionStart` source.** `resume` and `fork` keep the
conversation history, so the notices already given are still in context;
re-arming would repeat them (D21).
