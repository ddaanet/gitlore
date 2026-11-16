# Session and hook wiring

What every `SessionStart` does. The decisions that argue for that shape (D14,
D59, D74, D83) are in [session-decisions.md](session-decisions.md). The hook
wrapper files gitlore writes into the git common dir, and the decisions about
where they live and how they are anchored (D5, D11), are in
[hook-wrappers.md](hook-wrappers.md). The mid-session plugin-upgrade notice
(D21) has its own node, [plugin-upgrade-notice.md](plugin-upgrade-notice.md).
The install command that wires them is in
[installation.md](installation.md).

---

## The Session

Everything install wires is re-pinned, re-emitted or re-run at the start of
every session, except hook-manager wiring: `SessionStart` runs no command the
clone supplies, so it prints the recorded installer for the user to run.

**`SessionStart`.** Guards: if `gitlore.enabled` is not `true`, or `.gitmodules`
has no memory submodule entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started
   with a plain `claude` — memory is *not* redirected and will strand in the
   default directory. Say so on `systemMessage`, naming the fix (`direnv allow`,
   or the global shim on a machine without direnv). Nothing is written to any
   settings file; a value written there would not redirect until the next launch
   (D10).
2. **Re-pin the plugin-path key** `gitlore.hooksDir`, so a plugin upgrade heals
   itself.
3. **Emit the wrapper** `gitlore-pre-push` and the `gitlore-pre-commit` stub
   into the git common dir. Idempotent and worktree-agnostic (D11, in
   [hook-wrappers.md](hook-wrappers.md)).
4. **Read the hook-manager sentinel** after a clone or a new machine (`direct`
   re-runs the direct wiring; `manual` is a keyword; the three manager commands
   are printed for the user to run and nothing else is run, D45 — see
   [Hook Manager Support](installation.md#hook-manager-support)).
5. **Materialize the store.** Initialize the submodule if needed; add a memory
   worktree for a linked parent worktree; create local `live` from the
   checked-out gitlink (HEAD) after a clone without `--recurse-submodules`,
   since the branch model references `live` as a local ref — never from
   `origin/live`, which may be ahead of the gitlink (D59).
6. **Report where memory stands.** The retired store gate's `pre-commit` wrapper
   is removed from the memory store and each checked-out tier (D70).
   `report_memory_position` reads where it sits against the authority's `live`,
   the remote's or else its own, for the position line (D84). It moves nothing,
   detaches nothing and is never fatal; the pass continues whatever it reports.
7. **Repair a missing root index.** A store with no `MEMORY.md` — an install
   seeded from an auto-memory dir that existed but held nothing committed an
   empty tree — gets the `# Memory Index` scaffold written back as an
   uncommitted file, so it lands in the next FR11 commit under review rather
   than in a commit of its own, and `systemMessage` says so. Every step below
   assumes the file exists: composition places tier lines into it, a merge
   continuation stages it, and the dangling report reads pointers out of it.
8. **Report the tiers.** A tier that is not checked out is cloned at the commit
   the memory store's index records. A tier holding an unfinished merge is left
   as it is and named. Every other mounted tier stays on the commit it is on,
   its remote `live` is fetched read-only, bounded by `GITLORE_FETCH_TIMEOUT`
   (D83), and its position against the authority's `live` joins the position
   line (D84, [session-decisions.md](session-decisions.md)), with any recorded
   commit no repository holds reported on its own
   ([unresolvable-pin.md](unresolvable-pin.md)). A tier advances only through
   `/gitlore:merge` or `/gitlore:push` (D43). An unfetchable tier is reported by
   name, never silently skipped, because a tier that stops talking to its remote
   looks exactly like one with nothing to say.
9. **Report the store's diagnostics** and write no index (D74, in
   [session-decisions.md](session-decisions.md)): the rule problems of the
   indexes, a pending compose, then the dangling-pointer report (D34), which
   runs on every store.
10. **Drain this session's relay reports, then sweep by age.** A hook firing
   inside a subagent reports only to that subagent, so it writes its report to a
   file keyed by session and agent (D51, [cc-platform.md](cc-platform.md)). This
   folds in every report addressed to *this* session that no parent-side batch
   collected, framed with the agent that staged it — `compact` and `resume` keep
   the session id and fire no batch of their own, so this pass delivers at the
   resume itself rather than leaving a waiting report to the session's next
   batch. The sweep then removes every relay file older than seven days
   regardless of session, temps included: a report addressed to a session that
   ended is undeliverable, so it goes by age rather than into a stranger's
   session. No earlier step ends the pass, so a resume or compaction of the same
   session always collects what is waiting.
11. **Emit the standing orientation** on `additionalContext`: the FR11
   prohibition (D70) and the active tiers' own routing descriptions (D28).

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

The wrapper paths being gitlink-aware (D11, in
[hook-wrappers.md](hook-wrappers.md)) is what makes this *reachable* in a linked
worktree: a literal `.git/gitlore-*` aborts `emit-wrappers` under `set -e`
before step 5 runs, and blocks committing in the worktree outright.

> **Why not a `WorktreeCreate` hook.** Verified against CC 2.1.150
> (`claude-code-guide`, 2026-05-25): it is an **override** hook that fires
> *before* the worktree exists and must create it, printing only its path (extra
> stdout hangs CC, #27467). Its stdin carries no worktree path and no branch, it
> does not fire for Desktop-created worktrees, and there is no post-creation
> hook (#27744). Registering it would hijack worktree placement for zero benefit
> over the `SessionStart` path.

**`WorktreeRemove`** (advisory — cannot block). Input provides `worktree_path`
only (verified CC 2.1.150 — no branch field). A non-zero exit logs a warning but
cannot stop the removal. Guard: no-op if `.gitmodules` has no memory submodule
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
episode. It reports and never repairs; see D21 in
[plugin-upgrade-notice.md](plugin-upgrade-notice.md).

**`SessionStart(startup|clear|compact)` — the nudge reset.** `nudge-reset.sh`
re-arms the once-per-episode notices (index byte budget, plugin upgrade, missing
root index). Each marker claims "this session has already been told", and these
three sources end or condense the context that claim rests on. It sits in its
own matcher group of `hooks.json`, so the script never runs on `resume` or
`fork`, which keep the conversation and the notices in it; see D21 in
[plugin-upgrade-notice.md](plugin-upgrade-notice.md).

**`PostToolUse(EnterWorktree|ExitWorktree)` — the drift guard.**
`worktree-drift.sh` warns when an in-process worktree switch has moved the
session's cwd away from the repo whose memory is redirected. See D15.
