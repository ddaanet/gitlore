# Who commits memory — decisions D58, D70

Why no parent git operation and no hook commits memory, and why the agent
commits it itself: the decisions behind `commit-memory.sh`, which runs as
`gitlore-commit`. The script, its discovery by plugin `bin/` name and the shared
body are in [memory-entry-points.md](memory-entry-points.md); the wording of the
approval a commit carries is in [commit-gate.md](commit-gate.md); FR11 itself
stays in `design.md`.

- **D58** a memory commit is the agent's own act, never a side effect of a
  parent commit · **D70** the agent commits memory itself, the summary passed in
  the call and one section per store, the entry points reached by plugin `bin/`
  name

---

## Mechanism

The mechanism is in [memory-entry-points.md](memory-entry-points.md): the Memory
Commit Entry Point section holds `commit-memory.sh`, the pointer the commit
stages, discovery by `bin/` name and the shared body. The hook that remains,
`pre-push`, is in [git-hooks.md](git-hooks.md).

## Decisions — D58, D70

**D58 — A memory commit is the agent's own act, never a side effect of a parent
commit**

`commit-memory.sh` is the one commit path. The parent `pre-commit` hook, its
wiring and the `precommitCommand` nudge are retired, and a parent `git commit`
touches no memory.

**Why the hook went.** A parent commit over dirty memory met the FR11 approval
gate inside a git hook, which has no one to converse with: the refusal reached
whoever ran `git commit`, and a subagent's commits blocked on a summary only the
main conversation could obtain. The approval is a conversation, and a
conversation belongs to the agent that holds the user; a hook can only refuse
and hand the request back. With the commit made where the approval is obtained,
the hook has no work the script does not do.

**The pointer is staged by the commit.** The hook's last step staged the moved
gitlink into the index git handed it. The script stages it into the parent index
after a run that moved memory's HEAD, so the next parent commit records it with
no hook; between the memory commit and that parent commit the gitlink floats
(git-hooks.md). During a replay (rebase, cherry-pick, revert) the script skips
the staging and says so, because a replayed commit must keep the pointer it
recorded. FR11's approval stays: summarize, ask, then commit.

**Hook-manager configs are a published boundary; `.git/hooks/pre-commit` is
not.** A tracked `lefthook.yml`, `.husky/pre-commit` or `.overcommit.yml`
written by an earlier install names `gitlore-pre-commit` and travels to every
clone, so the installer cannot assume it was rewritten: `gitlore-pre-commit`
stays in the common dir as an exit-0 stub, and new wiring installs `pre-push`
only. The direct wiring wrote a file in the clone's own `.git/hooks`, which no
one else reads; `wire-direct.sh` removes that shim when it is byte-for-byte what
it wrote, strips the appended gitlore block from a hand-rolled hook, and leaves
any other `pre-commit` hook alone. `write-settings.sh` deletes a leftover
`gitlore.precommitCommand`.

**D70 — The agent commits memory itself, with the summary passed in the call**

The `gitlore:commit` skill carries the protocol and the summary format (D19):
the agent summarizes the pending changes, shows the summary, ends its turn, and
once the user's reply approves it runs `gitlore-commit <<'EOF'` from the repo
root with the approved summary, verbatim, as the heredoc body. That is the whole
commit protocol. One message per store keeps a private store's paragraphs out of
a shared tier's log, which a single summary committed into every store did not.
No hook commits authoring content: no `PostToolBatch` hook acts on a trigger
file, and no gate inside a store admits only commits carrying a sentinel.

**The approval lives in the conversation, so the commit goes where the
conversation is.** D58 moved the commit out of the parent `pre-commit` because a
hook has no one to converse with. A second hook in the loop would guard one
case: a denied Bash call stranding a summary the user already approved. A denial
strands nothing. The summary is in the transcript the agent holds, so a denial
costs one turn — the same call again, or behind a `!` prefix — which is the cost
D20 accepts for the push. The hook path would carry a message file whose
presence meant approval, an mtime freshness verdict deciding whether a retry
still held it, a restamp after every failure that prepared no merge, and outcome
arms read off the store after the run, all so that an approval could outlive the
call that used it. With the summary passed in the call, nothing outlives the
call, and a retry is the agent passing the summary again — re-approved in
conversation when the store has moved since.

**No gate inside the store.** A `pre-commit` in the store admitting any commit
carrying `GITLORE_MEMORY_COMMIT=1` and refusing the rest never sees an approval:
an agent can run `gitlore-commit` with a summary nobody approved as easily as it
can run `git commit`, and the 2026-10-11 eval (4 of 5 runs committed in the same
turn as the request) is that case, which such a gate admits. What it blocks is a
direct `git commit` in the store, which the `SessionStart` orientation already
forbids by role. Its cost is a sentinel on every commit site gitlore owns, a
wrapper emitted into every store's hooks dir, a `gitlore.hooksDir` mirrored into
every store's config, and a stale wrapper's "relaunch" hint whenever the plugin
cache moves. `SessionStart` removes a store's `pre-commit` wrapper, and unsets
the mirrored key, only when the hook contains the retired wrapper's line
`exec "$HOOKS_DIR/memory-pre-commit" "$@"`; any other `pre-commit` is the user's
and stays. So the orientation is the only control between the agent and an
authoring commit, and the entry says so rather than implying a backstop. A human
committing inside the store meets nothing, as with any git repository they own.

**The orientation carries the protocol, front-loaded.** `SessionStart` emits a
standing `additionalContext` every gitlore session, carrying the commit as an
act: writing a memory file is an ordinary edit; to commit memory, invoke the
`gitlore:commit` skill before drafting anything: it gives the summary format,
has the agent show the summary and end the turn, and after the user's reply
approves it runs `gitlore-commit` from the repo root with the approved summary
on stdin, through a quoted heredoc; never run `git commit` inside the memory
submodule. The text ends with the rule that a request to commit memory is not
approval of a summary the user has not seen: show the summary, end the turn,
commit only after the user's reply approves it. A summary passed with the call
counts as approved by construction, so this text is the only gate between the
agent and the commit; the eval above ran the command in the same turn in 4 of 5
runs, one stating it treated the request as the approval. The summary travels on
stdin and not as an argument because it is prose derived from memory content:
templated into a double-quoted argument, a backtick or `$(…)` in it would be run
by the agent's shell. The text is acts and nothing else: the hooks that no
longer exist are mechanism the agent cannot act on; the prohibition forbids by
role, because naming `git -C <mempath> commit` invites reasoning about the forms
left unnamed; and no FR id appears, since it resolves to nothing in the consumer
repos this context reaches. Pinned by the assertions in
`tests/cc_hook_session_start.bats`. The base Claude Code memory instructions
describe generic "edit files, save facts" memory with no review gate, so the
agent's default is actively wrong in a gitlore repo; the prohibition guards an
action the agent would otherwise take unprompted, so it must be front-loaded,
and no hook surfaces the command just in time. Writing stays seamless — no step
before an edit — and the approval step attaches to the commit alone.

**What a hook may still commit.** `pre-push` runs the take when a store is
behind its remote or a tier's `live` is ahead of its HEAD, and the take can land
D49's canned bookkeeping commit and D52's arrival repair. Neither authors
content — FR11 names both as its exemptions — so neither is what this decision
removes. No hook path commits anything else: `SessionStart` moves nothing (D59),
and the index hooks write files without committing them. Outside the hooks,
`gitlore-add-tier` also commits without an approved summary: it records a mount
or a create under a canned message when the memory store held no unapproved
work, and commits a created tier's seed in a scratch repository before mounting
it; that content follows from the request the user made (D71, in
[tiered-memory.md](tiered-memory.md)).

**Callers reach the entry points by name, not by a config key.** The plugin
ships `bin/gitlore-commit`, `bin/gitlore-push` and `bin/gitlore-merge`, each a
thin `exec` of `scripts/commit-memory.sh`, `scripts/push-memory.sh` or
`scripts/merge-memory.sh` resolved from the file's own location. Claude Code
puts each enabled plugin's `bin/` on the Bash tool's PATH, subagents included.
That serves the callers that have no `CLAUDE_PLUGIN_ROOT`, the agent's own Bash
first. The `handoff` plugin reaches memory commits through the skill, not a
file: on a dirty memory submodule its checkpoint tells the agent to invoke
`gitlore:commit`, and its parent commit records the gitlink `gitlore-commit`
staged — so renaming the skill or changing that staging breaks handoff without
an error. gitlore's own hooks have the variable and call
`$PLUGIN_ROOT/scripts/…`: a hook that calls a bare `bin/` name works in dogfood,
where the shim sets PATH on the whole process, and may fail once released. No
`gitlore.*Command` key exists, so nothing is seeded at install or re-pinned at
`SessionStart`, and no caller checks a resolved path is executable. PATH is
fixed at session start, so a plugin update mid-session leaves the name on the
old cache path until the next session. A disabled plugin makes the name "command
not found"; whether gitlore manages memory in a repo is still read from the
memory submodule registration in `.gitmodules` (FR12), never from the command's
existence. The in-repo dogfood session gets the same names:
`plugin-dev/bin/claude` appends `<root>/dist/plugin/bin` to PATH
unconditionally, and `just dogfood` ships `bin/` there because `dist.include`
lists it.

## Rejected alternatives

**The hook standing down on a missing approval.** Keeps the hook, its wiring,
the index capture and the replay guard alive for one case, and a refusing
`pre-commit` can abort a rebase. (D58)

**A `PreToolUse` hook constraining the agent's git operations.** Belt-and-braces
with real scoping complexity at the CC level. The drift it anticipated did
happen — a direct submodule commit bypassed FR11 — and D70 weighs the control
that answered it.

**An intent file and a `PostToolBatch` hook as a fallback for a denied call.**
The fallback was for a summary stranded by a denial, and a denial strands
nothing: the summary is in the transcript, and re-running costs one turn. It
carried a message file as the approval signal, a freshness verdict, failure
restamps and outcome arms, each added to keep a disk approval honest across
retries the direct call never makes (D70).

**A submodule `pre-commit` gate behind the conversational approval.** It
distinguishes a sentinel, not an approval, so it admits the unapproved commit
the eval measured and refuses only the direct `git commit` the orientation
already forbids. It costs a sentinel at every commit site, a wrapper and a
mirrored config key in every store, and stale-wrapper noise after each plugin
upgrade (D70).

**A bare `commit-memory.sh` retrying on an approval left on disk.** An approval
the caller did not just pass is exactly what a freshness verdict would have to
judge; with no hook caller, the only remaining caller holds the summary and can
pass it (D70).

**The summary transported through a well-known path in the parent working
tree.** A named path invites a caller to pre-write it, the alternative D16
refuses, and a leftover file reads as a pending approval. The text stays in the
process and reaches each commit on its stdin (D70).

**Unsetting `GIT_AUTHOR_*` and `GIT_COMMITTER_*` before every store commit.**
The leak it guards came from a store commit made inside the parent's
`pre-commit`, because `git commit` exports `GIT_AUTHOR_NAME`, `_EMAIL` and
`_DATE` to its hooks and `--local-env-vars` does not list them. D58 removed that
hook. The one git hook left, `pre-push`, can still commit through the take, but
`git push` exports none of those variables to it (probed on git 2.47.3: a
`pre-commit` saw all three, a `pre-push` none), and the `PostToolBatch` hooks
run under Claude Code with no git operation around them. An identity exported in
the user's own shell is their identity, not a leak. The scrub guards a state
nothing produces (D70).

**Keeping the `gitlore.*Command` discovery keys alongside the `bin/` names.**
Every caller the keys served runs in the Bash tool, where the names already
resolve, and the keys go stale exactly when PATH does. Kept, they are a second
discovery path to the same script, with a seed at install, a re-pin every
session, an executable check every caller is told to make, and tests for each.
The one caller they reach that PATH does not is a human in a terminal outside
Claude Code, and the commit there is not the human's path: it is the agent's act
(D58), and push and merge are skills (D20, D43).
