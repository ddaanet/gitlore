# 2026-10-11 — A memory commit is the agent's own act

**The parent `pre-commit` hook is gone, and a parent commit no longer touches
memory (D58).** `commit-memory.sh` — called directly, or reached through the
trigger file `memory-commit-batch.sh` acts on — is the one memory commit path.
Retired with the hook: its wiring in every hook-manager integration, the
`PostToolUse(Bash)` commit nudge (`post-tool-use.sh`), the
`gitlore.precommitCommand` key, the install's precommit-command argument, and
the nudge's `gitlore-nudged` marker.

The reason is where the approval gate sat. A parent commit over dirty memory met
the FR11 gate inside a git hook, which has no one to converse with: the refusal
went to whoever ran `git commit`, and a subagent's commits blocked on a summary
only the main conversation could obtain. The approval is a conversation, so the
commit moves to the agent that holds it: summarize, get the user's explicit
approval, then run `commit-memory.sh -m "<summary>"`.

**The script stages the pointer.** After a run that moved memory's HEAD it
stages the memory gitlink in the parent index, so the next parent commit records
it with no hook; the gitlink floats between a memory commit and that parent
commit. During a rebase, cherry-pick or revert it skips the staging and says so,
because a replayed commit must keep the pointer it recorded. A `git add` that
fails is reported and the script still exits 0, the memory commit having landed.
Pre-push ordering is unchanged, so NFR5 holds.

**Hook-manager configs are a published boundary; `.git/hooks/pre-commit` is
not.** A tracked `lefthook.yml`, `.husky/pre-commit` or `.overcommit.yml` from
an earlier install names `gitlore-pre-commit` and travels to every clone, so
`gitlore-pre-commit` stays in the common dir as an exit-0 stub and new wiring
installs `pre-push` only. The direct wiring wrote into the clone's own hooks
dir, which no one else reads: `wire-direct.sh` removes its old `pre-commit` shim
when it is byte-for-byte what it wrote, strips the appended gitlore block from a
hand-rolled hook, and leaves any other `pre-commit` hook alone.
`write-settings.sh` deletes a leftover `gitlore.precommitCommand`.

**`nudge-reset.sh` stays.** It never had to do with the commit nudge: it re-arms
three unrelated once-per-episode markers — the index byte budget, the plugin
upgrade and the missing root index — on `SessionStart` and `PreCompact`.

**Two earlier conclusions invert.** D16 held that the only blessed path to
commit memory is committing the parent; the standalone script is now the only
path. D12's orientation said committing the parent repo is all a memory write
needs; the `SessionStart` context now names `gitlore.commitCommand` and the
approval step, and keeps the prohibition on committing inside the submodule. The
submodule-side gate itself is unchanged, and its block message names
`commit-memory.sh`. The trigger file is no longer reserved for the handoff
plugin.

The rejected alternative is the hook standing down on a missing approval: it
keeps the wiring, the index capture and the replay guard alive for one case, and
a refusing `pre-commit` can abort a rebase.
