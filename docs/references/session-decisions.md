# Session decisions — D14, D59, D74, D83, D84

The decisions behind what every `SessionStart` does — D14, D59, D74, D83, D84.
The wiring they argue for, step by step, is in [session.md](session.md). The
table of what a module reports, which D84 reads, is in
[session.md](session.md).

- The session — **D14** user-facing SessionStart output goes on `systemMessage`
  · **D59** SessionStart moves no module; every advance is an explicit take or
  push · **D74** compose only where the edit happens; SessionStart reports and
  writes no index · **D83** SessionStart bounds every fetch it makes, and the
  `PostToolBatch` pass makes none · **D84** SessionStart reports every store's
  position in one line

---

## Decisions — D14, D59, D74, D83, D84

Why the wiring in [session.md](session.md) has this shape: what SessionStart
says to whom, and why it moves memory nowhere, writes no index and bounds its
fetches.

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

- **The position line** (D84) → `systemMessage` and `additionalContext`, the
  same text. The hook exits 0 throughout: stdout JSON is parsed only on exit 0,
  so a non-zero exit would discard the very message it was meant to signal, and
  SessionStart's exit code is consumed by nothing.
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

**The report.** Each module's position is read against the authority's `live`,
the remote's when the fetch brought it and local `live` where there is no remote
`live`, a failed fetch giving `unreachable` in its place, and is reported in the
one line of D84, below; the position table and the fetch-failure arms are in
[session.md](session.md#what-a-module-reports). A remote's git stderr can carry
`remote:` lines the remote chose, so it rides the user's channel only and the
agent's context gets a fixed sentence saying the user has it. A fetch that times
out reports `timed out after <n>s` in place of git's reason (D83).

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
contains its `HEAD` has the pending report withheld, and the position line names
the command: composing first dirties the tier, and the take then refuses it.
When the pass would change nothing, the orphan report runs instead, since a line
the tier added changes nothing in a pass; it is reported and never refused.

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
`timed out after <n>s`; the store's local position is not read, and the line
lists it `unreachable` (D84). My human partner: "sessionstart is useful because
it tells us to merge or push and it cannot answer this question without checking
remotes so maybe set a small timeout and report timed out". The
`submodule update --init` that clones a store not materialized is not bounded,
since a clone outlasts a fetch.

`SessionStart` fetches each store's `live` once per run, and the pin-guard yield
checks in its diagnostics reuse that outcome. The `PostToolBatch` pass runs no
fetch: it decides the yield from the refs as last fetched (internal
`GITLORE_NO_FETCH`), since it runs after every batch of edits and a network wait
there is paid by the agent's every turn. `gitlore-commit` and `gitlore-compose`
fetch each tier at most once per run, unbounded unless `GITLORE_FETCH_TIMEOUT`
is exported as a positive integer.

**D84 — SessionStart reports every store's position in one line**

One line, `gitlore: Run /gitlore:push (memory in sync; ddaanet diverged)`, or
`gitlore: memory in sync; ddaanet in sync` when no command is named, goes out
once on `systemMessage` and `additionalContext`, the same text, the all-in-sync
form included. A line listing one store has no separator. It stands as its own
paragraph on both channels and after any fetch-failure message of its run.
Stores come in order: `memory`, then each tier by name in `.gitmodules` order,
bare and unquoted.

The words are a closed set: `in sync`, `N ahead`, `N behind`, `diverged`,
`unreachable`, N never 0. `diverged` is position `forked` or `diverged` from
`gitlore_module_position`. `N ahead` counts the commits the store holds, `HEAD`
or local `live`, whichever is further, that the authority lacks. `N behind` is
measured from the checkout: the commits of the authority that `HEAD` lacks, or
when `HEAD` lacks none, those local `live` lacks, so a tier whose local `live`
equals `origin/live` and is two commits ahead of its `HEAD` reads `2 behind`.
`unreachable` is a failed fetch other than "couldn't find remote ref" or no
remote; it replaces whatever the local position is and names no command, and its
fetch-failure message keeps its text and channels.

The command is `/gitlore:push` when any listed store is `N ahead` or `diverged`,
else `/gitlore:merge` when any is `N behind`, else none. The rule is
[D76](publishing-divergence.md)'s taken over every listed store: any divergence
is published.

A store whose state has its own message and for which no push or merge is named
is left out and keeps that message: a memory store holding a merge, a tier with
an unfinished merge or that could not be checked out, a diverged store whose
rewrite check hit a recorded rewrite or could not run. A store with a lost pin
keeps its report and is listed with its position. With every store left out, no
line is printed. `memory — uncommitted changes present.` stays beside the line.

*One position line per store* (D59's form) names a command per store, and two
stores can name different ones. *Hint wording that tells `HEAD` diverged from
`live` from a divergence from the remote* ([D76](publishing-divergence.md)'s
text) is detail the command does not use: both name `/gitlore:push`. *A
diagnostics paragraph telling the user to run `/gitlore:merge` for tiers whose
local `live` is ahead of `HEAD`* could name a command other than the line's, so
those tiers are counted `N behind` and the pending-compose report is withheld
for them. *A status word carrying more than a position* (`dirty`, `mid-merge`)
mixes states that name no push or merge into a set that decides the command.

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
