# Session and hook wiring — decisions D14, D59, D74, D83

What every `SessionStart` does — followed by the decisions that argue for that
shape (D14, D59, D74, D83). The hook wrapper files gitlore writes into the git
common dir, and the decisions about where they live and how they are anchored
(D5, D11), are in [hook-wrappers.md](hook-wrappers.md). The mid-session
plugin-upgrade notice (D21) has its own node,
[plugin-upgrade-notice.md](plugin-upgrade-notice.md). The install command that
wires them is in
[installation.md](installation.md).

- The session — **D14** user-facing SessionStart output goes on `systemMessage`
  · **D59** SessionStart moves no module; every advance is an explicit take or
  push · **D74** compose only where the edit happens; SessionStart reports and
  writes no index · **D83** SessionStart bounds every fetch it makes, and the
  `PostToolBatch` pass makes none

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
   `report_memory_position` states where it sits against the authority's `live`,
   the remote's or else its own (D59, below). It moves nothing, detaches nothing
   and is never fatal; the pass continues whatever it reports.
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
   (D83), and it reports its position against the authority's `live` and any
   recorded commit no repository holds
   ([publishing-divergence.md](publishing-divergence.md),
   [unresolvable-pin.md](unresolvable-pin.md)). A tier advances only through
   `/gitlore:merge` or `/gitlore:push` (D43). An unfetchable tier is reported by
   name, never silently skipped, because a tier that stops talking to its remote
   looks exactly like one with nothing to say.
9. **Report the store's diagnostics** and write no index (D74, below): the rule
   problems of the indexes, a pending compose, then the dangling-pointer report
   (D34), which runs on every store.
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

## Decisions — D14, D59, D74, D83

Why the wiring above has this shape: what SessionStart says to whom, and why it
moves memory nowhere, writes no index and bounds its fetches.

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

**D59 — SessionStart moves no module; every advance is an explicit take or
push**

A module is the memory store or a tier. A hook that fast-forwarded a clean HEAD
onto `live` has no work in a single checkout: the store is sized for one clone
per project, HEAD and `live` agree by construction there (a commit advances
both, D41), and a fresh clone makes `live` from the gitlink HEAD. The one case
it served is a separately launched linked worktree, whose HEAD lags a `live`
another checkout advanced — and a move the user did not see changes the checkout
under their edits without a word. A tier re-pinned to its gitlink at every
session, or advanced to its remote's `live`, has the same fault, and the first
is also the loop that made a tier ahead of its gitlink unreachable: the session
discarded the position a take or a commit had just put it in. So the hook
reports and `/gitlore:merge` takes (the local move is in
[merge-and-resolve.md](merge-and-resolve.md)); a parent push still takes a
behind remote (D49). It clones a module that is not materialized, which moves
nothing that exists.

**The report.** Each module's position against the authority's `live` is one
line, on `systemMessage` and, where it names an act, on `additionalContext`
(`add_report`); the authority is the remote's `live` when the fetch brought it
and local `live` otherwise. The table, the lines and the fetch-failure arms are
in [publishing-divergence.md](publishing-divergence.md) (D76). A remote's git
stderr can carry `remote:` lines the remote chose, so it rides the user's
channel only and the agent's context gets a fixed sentence saying the user has
it. A fetch that times out reports `timed out after <n>s` in place of git's
reason (D83).

**D74 — Compose only where the edit happens; SessionStart reports and writes no
index**

`PostToolBatch` and the mount are the only writers of an index in a session. The
end of an explicit take and a memory merge's continuation write root up from the
tiers, which is the take's own bookkeeping (D77), and `gitlore-compose`, run by
hand, clears what no batch will. The commit aborts on a pending compose (D50, in
[git-hooks.md](git-hooks.md)). `SessionStart` reports position and store
diagnostics and writes no index.

The reason is the one D50 gives for the commit: anything `PostToolBatch` did not
compose is assumed to be an exterior change — a human in an editor, a dead hook,
a manifest edit in a terminal — and failing on it beats silently fixing it. A
compose at session start writes a carrier no summary described and no session
saw, and the next commit publishes it.

**The diagnostics** are read-only, each on `systemMessage` and
`additionalContext` (`add_report`), so the agent holds the command that clears
it:

- *Rule problems* — `gitlore_compose_check`: a duplicate, welded or interleaved
  line, an unattributable prefix, a manifest tier that is not mounted.
- *A pending compose* — `gitlore_compose_pending`: the indexes a pass would
  change, with `gitlore-compose`.
- *Dangling pointers* (D34) — on every store, refused or not.

`gitlore_compose_pending` runs over every tier wherever it sits: the check is
read-only, and a tier off its pin is one of the problems it reports, naming the
take. Two states hold it back, and only the rule problems are reported over
them: a prepared merge in memory or any tier, whose own notice is the report and
whose merged index is the merger's business (`gitlore_store_mid_merge`, which
also covers a state file), and a tier whose recorded commit no repository holds,
which composes nothing and has its own report
([unresolvable-pin.md](unresolvable-pin.md)). A tier off its pin is a rule
problem the pass reports by name, except one the pin guard yields (D50), which
the report and the orphan report pass over. A tier whose local `live` strictly
contains its `HEAD` gets `/gitlore:merge` in place of `gitlore-compose`:
composing first dirties the tier, and the take then refuses it. When the pass
would change nothing, the orphan report runs instead, since a line the tier
added changes nothing in a pass; it is reported and never refused.

A registered tier with no checkout does not hold the pending report back: a
compose keeps its root lines and writes no carrier for it. The dangling report
leaves those lines out, because they are not stale. The tier stage's "could not
be checked out" notice is its report, on both channels: the agent's line says
the tier's facts are not available in this session and its index lines stay.

**D83 — SessionStart bounds every fetch it makes; the `PostToolBatch` pass makes
none**

`SessionStart` earns its place by telling the user to merge or push, and it
cannot answer which without asking the remote, so it fetches. A remote that is
slow or prompts for credentials must not stall the session, so each fetch it
makes, memory's and each tier's `live` and the rewrite record, runs under a
timeout in seconds from `GITLORE_FETCH_TIMEOUT`, default 5 (a value that is not
a positive integer reads as 5). A fetch past it is killed with its process
group, `SessionStart` completes, and the store's could-not-fetch report says
`timed out after <n>s`; the module's position is then read against local `live`.
My human partner: "sessionstart is useful because it tells us to merge or push
and it cannot answer this question without checking remotes so maybe set a small
timeout and report timed out". The `submodule update --init` that clones a store
not materialized is not bounded, since a clone outlasts a fetch.

`SessionStart` fetches each store once per run, and the pin-guard yield checks
in its diagnostics reuse that outcome, so one slow remote costs one timeout. The
`PostToolBatch` pass runs no fetch: it decides the yield from the refs as last
fetched (internal `GITLORE_NO_FETCH`), since it runs after every batch of edits
and a network wait there is paid by the agent's every turn. `gitlore-commit` and
`gitlore-compose` fetch each tier at most once per run, unbounded unless
`GITLORE_FETCH_TIMEOUT` is exported as a positive integer.

## Rejected alternatives

**Deciding from last-fetched state only, at `SessionStart`.** The merge or push
hint is the report's value, and it is a function of the remote's `live`; refs
last fetched may be days old and name the wrong act.

**An unbounded fetch in a hook.** A slow or prompting remote stalls every
session start (D83).

**Composing at `SessionStart`.** A store that arrives with an index off its
composition was changed outside a batch. Composing it at session start repairs
it silently: a line deleted from a carrier alone, or a line added to the root
outside a session, is rewritten without anything saying so, and the repair ships
in the next commit under a summary that does not describe it. Composing a tier
whose local `live` is ahead of its pin also dirties it, and the take then
refuses it (D74).

**Composing at the commit.** The commit is the last point at which an exterior
change can be told apart from the session's own edits, and composing there hides
it from the session that made it (D50, D74).

**Splitting `gitlore_compose_pass` for a read-only caller.** Lifting the part
after the refusal check into its own function would let the pending report skip
the pin check and run beside a tier behind its pin. It buys a report for a store
that already has a louder one, and needs the mid-merge and lost-pin tiers
filtered out of a second copy of the loop by hand (D74).

**The clean-only fast-forward at session start.** It does no work in a single
checkout, where HEAD equals `live` already. In the multi-checkout case a take
the user sees beats a move they cannot: the report names the commits and the
command, and the checkout changes when they run it (D59).

**Moving a tier at `SessionStart`.** Re-pinning each tier to its gitlink, or
advancing it, changes a checkout under the user's edits and discards the
position a take or a commit just put the tier in; a tier ahead of its gitlink is
left where it stands because the take needs it there to compose its lines up
(D78), and the pin guard's report names that take. The hook clones a missing
tier and reports the rest (D59).

**A `WorktreeCreate` hook to set up the memory worktree.** It is an override
hook — it fires before the worktree exists, must create it, and must print only
its path (extra stdout hangs CC, #27467) — carries no branch in stdin, and never
fires for Desktop-created worktrees. `SessionStart` in the new worktree covers
every case with none of that (verified CC 2.1.150).
