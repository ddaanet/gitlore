# Session and hook wiring — decisions D5, D11, D14, D21

The hook wrapper files gitlore writes into the git common dir, and what every
`SessionStart` does — followed by the decisions that argue for that shape (D5,
D11, D14, D21). The install command that puts them there is in
[installation.md](installation.md).

- Wrappers and the session — **D5** wrapper scripts live in the git common dir,
  untracked · **D11** wrapper paths are gitlink-aware, anchored at the common
  dir, for linked worktrees · **D14** user-facing SessionStart output goes on
  `systemMessage` · **D21** a mid-session plugin upgrade is a notice, not a
  self-healing config

---

## Hook Wrappers

`SessionStart` writes two flat files into the repo's **git common dir** on every
startup, resolved via `git rev-parse --git-common-dir`:

- `<common-dir>/gitlore-pre-commit`
- `<common-dir>/gitlore-pre-push`

The common dir is shared across all worktrees (`--git-common-dir` → `.git` in
the main worktree, `<main>/.git` in a linked one), so one emission is reachable
and executable from every worktree — including one where no Claude session has
ever run. Every producer (`emit-wrappers`) and every consumer (the wired stubs
and manager configs) resolves the wrapper through `--git-common-dir`; none
hardcode `.git/`, which is a gitlink *file* in a linked worktree. See D11.

Each wrapper delegates to the current plugin via `git config gitlore.hooksDir`
(regular git config, shared across worktrees via the common config). Stable
paths for hook manager configs; plugin updates are transparent. If
`gitlore.hooksDir` is unset (a plain `git commit` outside any Claude session
before SessionStart has fired), the wrapper exits 0 after emitting a stderr hint
— `"gitlore skipped: hooks not installed"` plus instructions to install the
marketplace, plugin, and start Claude.

```sh
#!/bin/sh
HOOKS_DIR=$(git config gitlore.hooksDir)
if [ -z "$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "$HOOKS_DIR/pre-commit" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Relaunch Claude Code in this repo with 'claude -c' to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "$HOOKS_DIR/pre-commit" "$@"
```

## The Session

Everything install wires is re-pinned, re-emitted or replayed at the start of
every session, which is what makes a clone, a new machine and a plugin upgrade
heal themselves.

**`SessionStart`.** Guards: if `gitlore.enabled` is not `true`, or `.gitmodules`
has no `gitlore-memory` entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started
   with a plain `claude` — memory is *not* redirected and will strand in the
   default directory. Say so on `systemMessage`, naming the fix (`direnv allow`,
   or the global shim on a machine without direnv). Nothing is written to any
   settings file; that tier is ignored (D10).
2. **Re-pin the five plugin-path keys** — `gitlore.hooksDir`,
   `gitlore.commitCommand`, `gitlore.pushCommand`, `gitlore.mergeCommand`,
   `gitlore.memoryApprovalClauseFile` — so a plugin upgrade heals itself.
3. **Emit the wrappers** `gitlore-pre-commit` and `gitlore-pre-push` into the
   git common dir, and the FR11 commit gate into the memory store and each tier.
   Idempotent and worktree-agnostic (D11, D12).
4. **Replay the hook-manager sentinel** to reinstate wiring after a clone or a
   new machine (`direct` and `manual` are keywords; the three manager commands
   are matched as literals and nothing else is run, D45 — see Hook Manager
   Support above).
5. **Materialize the store.** Initialize the submodule if needed; add a memory
   worktree for a linked parent worktree; create local `live` from `origin/live`
   (or from the checked-out gitlink when there is no remote) after a clone
   without `--recurse-submodules`, since the branch model references `live` as a
   local ref.
6. **Detach at `live` and fast-forward**, or skip the fast-forward with a notice
   when memory is dirty. A fast-forward that fails is divergence: report it and
   route to `/gitlore:resolve`.
7. **Pin the tiers.** A tier holding an unfinished merge is left as it is and
   named, because the checkout below would clear its `MERGE_HEAD`. Every other
   mounted tier is initialized and checked out at the gitlink the memory
   store's index records, detached in place if it arrived on a branch, and its
   remote `live` is fetched read-only to name what is waiting — upstream facts,
   or a divergence — without moving anything: a tier advances only through
   `/gitlore:merge` or `/gitlore:push` (D43). An unfetchable tier is reported
   by name, never silently skipped, because a tier that stops talking to its
   remote looks exactly like one with nothing to say.
8. **Compose the indexes**, then run the dangling-pointer report (D34). A
   refusal writes nothing and says why; a partial write says which indexes are
   composed.
9. **Emit the standing orientation** on `additionalContext`: the FR11
   prohibition (D12) and the active tiers' own routing descriptions (D28).

**Worktree creation — handled by `SessionStart`, not a `WorktreeCreate` hook.**
Memory-worktree setup for a new worktree happens lazily at the next
`SessionStart` in that worktree:

```sh
git -C <main-repo>/.git/modules/gitlore-memory worktree add --detach <worktree-path>/<memory-rel-path> live
```

This is uniform across every way a worktree comes into being:

- **`claude --worktree <name>`** — starts a *new session* in the new worktree,
  so `SessionStart` fires there with `cwd` = the worktree path (verified, CC
  2.1.150).
- **Manual `git worktree add`** — next `SessionStart` in that worktree handles
  it.
- **Claude Desktop's worktree button** — does not fire `WorktreeCreate` at all
  (CC #57209), but a session still starts there, so `SessionStart` covers it.

Lazy creation is correct: with no session there is no auto-memory being written,
so there is nothing to set up until the first session needs it.

The wrapper paths being gitlink-aware (D11) is what makes this *reachable* in a
linked worktree: a literal `.git/gitlore-*` aborts `emit-wrappers` under
`set -e` before step 5 runs, and blocks committing in the worktree outright.

> **Why not a `WorktreeCreate` hook.** Verified against CC 2.1.150
> (`claude-code-guide`, 2026-05-25): `WorktreeCreate` is an **override** hook —
> it fires *before* the worktree exists, the script is expected to *create* it
> and print only its absolute path on stdout, and any extra stdout makes CC hang
> (#27467). Its stdin carries `{hook_event_name, cwd, name}` — **no** worktree
> path and **no** branch (CC defaults the branch to `worktree-<name>`);
> `hookSpecificOutput.worktreePath` is an HTTP-hooks-only *output* field. It
> also does not fire for Desktop-created worktrees, and there is no
> post-creation hook (#27744). Registering it would mean hijacking worktree
> placement for zero benefit over the `SessionStart` path.

**`WorktreeRemove`** (advisory — cannot block). Input provides `worktree_path`
only (verified CC 2.1.150 — no branch field). A non-zero exit logs a warning but
cannot stop the removal. Guard: no-op if `.gitmodules` has no `gitlore-memory`
entry.

1. Derive the memory submodule worktree path as
   `<worktree_path>/<memory-rel-path>`. If it is not a registered memory
   worktree (e.g. no session ever ran there, or an ephemeral subagent worktree),
   no-op. Otherwise
   `git -C <memory-gitdir> worktree remove <memory-submodule-worktree-path>`
   (prune if the directory is already gone). On failure (locked, uncommitted
   changes), emit a warning; never block parent worktree removal.
2. Nothing else is removed. CC leaves the parent branch in place on worktree
   removal (verified 2.1.150, #28422, #38287), and memory carries no named
   branch of its own; `live` is shared and survives. Gitlore never touches
   parent branches.

**`PostToolBatch` — the plugin-upgrade notice.** `plugin-upgrade-batch.sh`
compares the plugin root this session froze at against what the install record
says is installed for this repo, and reports a mid-session upgrade once per
episode. It reports and never repairs; see D21.

**`SessionStart` and `PreCompact` — the nudge reset.** `nudge-reset.sh` re-arms
the once-per-episode notices (index byte budget, plugin upgrade). Both markers
claim "this session has already been told", and both events end the context that
claim rests on; see D21.

**`PostToolUse(EnterWorktree|ExitWorktree)` — the drift guard.**
`worktree-drift.sh` warns when an in-process worktree switch has moved the
session's cwd away from the repo whose memory is redirected. See D15.

## Decisions — D5, D11, D14, D21

Why the wiring above has this shape: where the wrappers live and how they are
anchored, what SessionStart says to whom, and why a mid-session plugin upgrade
is a notice rather than a repair.

**D5 — Wrapper scripts in the git common dir, not tracked**

Tracking hook scripts in the repo would cause commit churn on every plugin
update and couple the repo's history to the plugin's versioning. Storing flat
wrappers in the git common dir (`<common-dir>/gitlore-pre-commit`,
`<common-dir>/gitlore-pre-push`, resolved via `git rev-parse --git-common-dir`)
keeps them untracked and local. `SessionStart` regenerates them on every
startup, so they always reflect the current plugin version. The common dir
(rather than a literal `.git/`) is what makes the wrappers reachable from linked
worktrees, where `.git` is a gitlink file — see Hook wrappers above and **D11**.

Wrappers exec the real hook scripts via `$(git config gitlore.hooksDir)/<hook>`.
The wrapper degrades to a clean skip (exit 0 + stderr hint) in **two** cases,
not one:

1. **`gitlore.hooksDir` unset** — a plain `git commit` outside any Claude
   session before SessionStart has fired. Hint: install the marketplace, plugin,
   and start Claude.
2. **`gitlore.hooksDir` set but `$HOOKS_DIR/<hook>` does not exist** — the
   version-pinned config points at a plugin-cache dir that was GC'd after a
   plugin upgrade, in the window before the next SessionStart re-pins it.
   Without this guard the wrapper `exec`s a missing path and the commit/push
   **hard-fails** with `exec: …: not found`. Hint: relaunch with `claude -c`.

Both keep git operations unblocked rather than breaking a commit on a
transient/stale-config condition.

**The refresh is `claude -c`, not a cold session.** Any process start re-pins
the five keys — `SessionStart` fires on a resume as it does on a startup, with
`source=resume` (D21) — so a resume closes the staleness window while keeping
the conversation that hit it. A cold session closes the same window and throws
the context away. This is the same remedy the upgrade notice names, for the same
reason: what went stale was frozen at process start, and only a new process
re-reads it.

**D11 — Gitlink-aware wrapper paths (common-dir anchor) for linked-worktree
support**

A literal relative `.git/gitlore-<hook>` in the wrapper writer (`emit-wrappers`)
and in the hook-manager consumers works only where `.git` is a directory — the
main worktree. In a linked worktree `.git` is a gitlink *file*, so the path
fails on both sides: `cat > .git/gitlore-*` aborts SessionStart under `set -e`,
and the shared wired hook (which lives in the common dir and therefore fires in
*every* worktree) `exec`s the literal path and **blocks the commit**
(`exec: … not found`). Both verified empirically against git 2.47.3.

The wrapper is therefore anchored at
`$(git rev-parse --git-common-dir)/gitlore-<hook>` on both the write and exec
sides, across all managers (direct, husky, lefthook, overcommit, manual). The
common dir is shared, so one emission covers every worktree, including a
session-less linked worktree (plain `git worktree add` + `git commit`).

Considered and rejected: a **per-worktree** anchor via
`git rev-parse --git-path gitlore-<hook>` (which resolves to
`…/worktrees/<name>/gitlore-<hook>`). It reintroduces the commit-blocking gap in
any worktree where no session has run yet, because the shared wired stub would
`exec` a per-worktree wrapper that does not exist. The common-dir anchor has no
such gap. (The commit-message file legitimately uses the per-worktree
`--git-path` because each worktree has its own pending message; the wrapper is
the opposite — one shared executable.)

Corollary fix: once the wrapper *fires* in a linked worktree, the git-hook runs
`git -C "$mempath" …` under `set -e`. If the memory submodule worktree was never
created there (session-less worktree), this would abort and block the commit for
a *new* reason. Both `pre-commit` and `pre-push` therefore guard with an early
`[ -e "$mempath/.git" ] || exit 0` — nothing to sync, never block.

**D14 — User-facing SessionStart output on `systemMessage`**

The Claude Code hook output channels (characterized 2026-06-10): `systemMessage`
(top-level JSON field) is the only reliably user-visible channel;
`hookSpecificOutput.additionalContext` is injected into the model's context but
**never echoed to the user**; stdout is consumed as JSON and not echoed; stderr
is shown to the user only on exit code **2** (or any non-zero under
`--verbose`). SessionStart is non-blocking — the session continues regardless of
exit code.

A notice on stderr is therefore effectively invisible, and a silent success path
leaves the user with no confirmation that memory is wired at all. Routing
notices through the agent (`additionalContext` "tell the user…") is rejected: it
puts the model on the hot path against NFR1/D7.

Every user-facing SessionStart notice rides `systemMessage`, accumulated into
the single SessionStart JSON the hook writes to fd 3:

- **Divergence** error → `systemMessage` + `exit 0`. Exit 0 because stdout JSON
  is parsed only on exit 0, so a non-zero exit would discard the very message it
  was meant to signal, and because SessionStart's exit code is non-blocking and
  consumed by nothing. The script still halts there, before the tier propagation
  pass.
- **Dirty-skip** notice → `systemMessage`, informational.
- **Clean success** → a brief confirmation (`memory ready (detached at live)`),
  per the chosen always-confirm behaviour.
- **Launcher-not-redirected** warning → `systemMessage`; when present it leads
  the message and the state line follows.

`additionalContext` carries the standing commit-protocol orientation (D12) on
every path. The agent-vs-user text branch (`gitlore_say_for_agent_or_user`)
exists only for the git hooks (`pre-commit` / `pre-push` / `memory-pre-commit`),
which run outside a session where `CLAUDECODE` may be unset; SessionStart always
runs in-session, so its notices are written directly for the user.

**D21 — A mid-session plugin upgrade is a notice, not a self-healing config**

`CLAUDE_PLUGIN_ROOT` is resolved once, at process start, from
`~/.claude/plugins/installed_plugins.json`. That record keeps moving while a
session runs: another repo's session installs, or the user runs
`/plugin update`. Everything this session froze at start then belongs to the
*old* version — hook event registration, skill bodies, agent definitions, and
the five `gitlore.*` keys that point into the plugin root (D5). The
`PostToolBatch` hook `plugin-upgrade-batch.sh` notices the disagreement and
names the remedy, once per episode.

**Everything frozen at process start is re-read on a resume, so `claude -c` is
the entire remedy.** Verified 2026-07-31 by a two-run `--plugin-dir` probe whose
`SessionStart` hook logged its root and the payload's `source`, with
`hooks.json` rewritten between runs: the second run fired `SessionStart` with
`source=resume` and ran the **new** command, under the **same** `session_id`.
The transcript records no plugin path or version, so a resumed process has no
stale root to restore — it re-resolves the root from the install record, re-pins
the five keys, re-emits the wrappers and re-wires the memory gate exactly as a
cold start does, and the conversation survives. Nothing available inside a live
session substitutes for it.

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
precede it: no `CLAUDE_PLUGIN_ROOT`, no `gitlore-memory` submodule, and a frozen
root outside the plugin cache — the last because a `--plugin-dir` checkout is
never stale, and its parent is an ordinary source directory whose neighbours the
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

**Once per episode, re-armed by a compaction.** A marker in the memory store's
gitdir, keyed by session and swept after seven days, mirrors the index
byte-budget nudge; `nudge-reset.sh` clears both at `SessionStart` and
`PreCompact`. A compaction re-arms the notice deliberately: what survives is a
summary, and the session is still running the old root.

## Rejected alternatives

**Tracked hook scripts in the repo.** Commit churn on every plugin update, and
it couples the repo's history to the plugin's versioning.

**A literal `.git/gitlore-<hook>` wrapper path.** Fails in a linked worktree,
where `.git` is a gitlink file: the write aborts SessionStart and the exec
blocks the commit. Replaced by the common-dir anchor (D11).

**A per-worktree wrapper anchor** (`--git-path gitlore-<hook>`). Reintroduces
the commit-blocking gap in any worktree where no session has run, because the
shared wired stub would exec a per-worktree wrapper that does not exist. The
common-dir anchor has no such gap (D11).

**A `WorktreeCreate` hook to set up the memory worktree.** It is an override
hook — it fires before the worktree exists, must create it, and must print only
its path (extra stdout hangs CC, #27467) — carries no branch in stdin, and never
fires for Desktop-created worktrees. `SessionStart` in the new worktree covers
every case with none of that (verified CC 2.1.150).

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
