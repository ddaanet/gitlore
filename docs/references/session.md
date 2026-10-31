# Session and hook wiring — decisions D14, D59

What every `SessionStart` does — followed by the decisions that argue for that
shape (D14, D59). The hook wrapper files gitlore writes into the git common dir,
and the decisions about where they live and how they are anchored (D5, D11), are
in [hook-wrappers.md](hook-wrappers.md). The mid-session plugin-upgrade notice
(D21) has its own node, [plugin-upgrade-notice.md](plugin-upgrade-notice.md).
The install command that wires them is in
[installation.md](installation.md).

- The session — **D14** user-facing SessionStart output goes on `systemMessage`
  · **D59** SessionStart moves memory nowhere; every advance is an explicit take
  or push

---

## The Session

Everything install wires is re-pinned, re-emitted or replayed at the start of
every session, which is what makes a clone, a new machine and a plugin upgrade
heal themselves.

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
4. **Replay the hook-manager sentinel** to reinstate wiring after a clone or a
   new machine (`direct` and `manual` are keywords; the three manager commands
   are matched as literals and nothing else is run, D45 — see
   [Hook Manager Support](installation.md#hook-manager-support)).
5. **Materialize the store.** Initialize the submodule if needed; add a memory
   worktree for a linked parent worktree; create local `live` from the
   checked-out gitlink (HEAD) after a clone without `--recurse-submodules`,
   since the branch model references `live` as a local ref — never from
   `origin/live`, which may be ahead of the gitlink (D59).
6. **Detach in place and report where memory stands.** HEAD is detached without
   moving. The retired store gate's `pre-commit` wrapper is then removed from
   the memory store and each checked-out tier (D70). `report_memory_position`
   states where it sits against local `live` and against the remote's `live`
   (D59, below). It moves nothing and is never fatal; the pass continues
   whatever it reports.
7. **Repair a missing root index.** A store with no `MEMORY.md` — an install
   seeded from an auto-memory dir that existed but held nothing committed an
   empty tree — gets the `# Memory Index` scaffold written back as an
   uncommitted file, so it lands in the next FR11 commit under review rather
   than in a commit of its own, and `systemMessage` says so. Every step below
   assumes the file exists: composition places tier lines into it, a merge
   continuation stages it, and the dangling report reads pointers out of it.
8. **Pin the tiers.** A tier holding an unfinished merge is left as it is and
   named, because the checkout below would clear its `MERGE_HEAD`. Every other
   mounted tier is initialized and checked out at the gitlink the memory store's
   index records, detached in place if it arrived on a branch, and its remote
   `live` is fetched read-only to name what is waiting — upstream facts, or a
   divergence — without moving anything: a tier advances only through
   `/gitlore:merge` or `/gitlore:push` (D43). An unfetchable tier is reported by
   name, never silently skipped, because a tier that stops talking to its remote
   looks exactly like one with nothing to say.
9. **Compose the indexes**, then run the dangling-pointer report (D34). A
   refusal writes nothing and says why; a partial write says which indexes are
   composed.
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

## Decisions — D14, D59

Why the wiring above has this shape: what SessionStart says to whom, and why it
moves memory nowhere.

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

- **Position reports** (D59) → `systemMessage`, and `additionalContext` too for
  the ones that name an act. The hook exits 0 throughout: stdout JSON is parsed
  only on exit 0, so a non-zero exit would discard the very message it was meant
  to signal, and SessionStart's exit code is consumed by nothing.
- **Clean success** → a brief confirmation (`memory ready`), per the chosen
  always-confirm behaviour.
- **Launcher-not-redirected** warning → `systemMessage`; when present it leads
  the message and the state line follows.

`additionalContext` carries the standing commit-protocol orientation (D70) on
every path. The agent-vs-user text branch (`gitlore_say_for_agent_or_user`)
exists only for the git hook (`pre-push`) and the commit and push scripts, which
run where `CLAUDECODE` may be unset; SessionStart always runs in-session, so its
notices are written directly for the user.

**D59 — SessionStart moves memory nowhere; every advance is an explicit take or
push**

The hook used to fast-forward a clean HEAD onto `live`. A single checkout never
has work for it: the store is sized for one clone per project, HEAD and `live`
agree by construction there (a commit advances both, D41), and a fresh clone
makes `live` from the gitlink HEAD. The one case it served is a separately
launched linked worktree, whose HEAD lags a `live` another checkout advanced —
and a move the user did not see changes the checkout under their edits without a
word. So the hook reports and `/gitlore:merge` takes (the local move is in
[merge-and-resolve.md](merge-and-resolve.md)); a parent push still takes a
behind remote (D49).

**The report.** Each position is one line, on `systemMessage` and, where it
names an act, on `additionalContext` (`add_report`):

- *Dirty* — uncommitted changes present.
- *`live` strictly ahead of HEAD, clean* — N commits on `live` not checked out
  here, run `/gitlore:merge`. A dirty store says only the dirty line, because
  merge will not move a dirty HEAD.
- *HEAD and `live` diverged* — run `/gitlore:resolve`, then start a fresh
  session.
- *HEAD at `live`, clean* — `memory ready (detached at live).`, user channel
  only.
- *HEAD ahead of `live`, clean* — `memory ready.`, user channel only: nothing
  for this session to take, yet a state a store legitimately rests in, and
  saying nothing would leave the `systemMessage` empty.

**The remote.** For a real remote (not the install placeholder, not none) the
hook then runs `fetch origin live` — read-only, with no refspec, so it moves no
local branch and updates only `origin/live`. `origin/live` strictly ahead
reports N upstream commits, run `/gitlore:merge`; diverged from `live` reports
that upstream has diverged, run `/gitlore:merge` to reconcile; equal, or `live`
ahead (a push's business), is silent. A remote that has no `live` ref is silent:
there is nothing upstream to take, and the report would otherwise fire in every
store that was never published. Any other fetch failure is named, because an
unreachable remote looks exactly like one with nothing to say. git's own message
rides the user's channel only: its stderr can carry `remote:` lines the remote
chose, and the agent's context gets a fixed sentence saying the user has it.

## Rejected alternatives

**The clean-only fast-forward at session start.** It does no work in a single
checkout, where HEAD equals `live` already. In the multi-checkout case a take
the user sees beats a move they cannot: the report names the commits and the
command, and the checkout changes when they run it (D59).

**A `WorktreeCreate` hook to set up the memory worktree.** It is an override
hook — it fires before the worktree exists, must create it, and must print only
its path (extra stdout hangs CC, #27467) — carries no branch in stdin, and never
fires for Desktop-created worktrees. `SessionStart` in the new worktree covers
every case with none of that (verified CC 2.1.150).
