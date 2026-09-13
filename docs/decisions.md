# gitlore Design Decisions

The decisions index of the living design, [design.md](design.md): every decision
the project has taken, as a one-line conclusion, and every rejected alternative,
by name. This is the file to have in front of you when weighing a new decision —
a conclusion missing from here is one that gets re-litigated, silently. The
argument behind each conclusion — what was weighed, what was rejected, and why —
lives in the `docs/references/` node its group names, one hop away, and
`scripts/check-docs-links.py` gates that every conclusion here has an argument
there and every argument there a conclusion here.

---

## Design Decisions

**Merge and resolve** — the branch model and the divergence path.
[merge-and-resolve.md](references/merge-and-resolve.md)

- **D1** — `live` is the memory trunk, decoupled from the parent's default
  branch
- **D2** — superseded by D41's detached-at-`live` model; kept for the record
- **D3** — ordinary checkout during resolve, not git plumbing
- **D6** — merge direction: the more-authoritative side is the first parent
- **D7** — scripts decide, the agent handles language
- **D9** — a sub-agent synthesizes the merge (requires the experimental flag)
- **D13** — a lock-contention retry wrapper guards mutating memory git calls
- **D24** — a directive that names a sub-agent carries its own authorization
- **D41** — detached at `live`: one branch model, one commit path, every store
- **D49** — canned unprompted merge commits; takes commit their bookkeeping

*Rejected:* `live` as a working branch · `git commit-tree` plus `git update-ref`
for the resolve merge · a temporary worktree for resolve · `claude --print` for
conflict resolution · single-agent resolve with a post-hoc context refresh.

**The commit gate** — FR11's approval machinery.
[commit-gate.md](references/commit-gate.md)

- **D4** — commit message by file handshake; its presence is the approval signal
- **D12** — a submodule-side commit gate backs FR11 as defense in depth
- **D19** — one canonical approval clause, discovered via a git-config key
- **D22** — the memory-hygiene checker is a repo-local gate, not shipped surface

*Rejected:* a `Stop` hook to generate the commit message · `PostToolUse` on
every memory `Write`/`Edit` · an interactive prompt inside the `pre-commit` hook
· an in-session diff dump for commit review · a `PreToolUse` hook constraining
the agent's git operations.

**Git hooks** — what `pre-commit` and `pre-push` do inside a parent git
operation, and the pointer invariant that rests on them.
[git-hooks.md](references/git-hooks.md)

- **D46** — a parent commit is never rewritten to re-pin memory
- **D50** — the commit path composes the store before it commits; a pin refusal
  aborts, a compose refusal only reports

*Rejected:* a tip amend to re-pin memory · a refusal that instructs the agent to
run compose · reporting an off-pin tier and committing through it · recognising
gitlore's own landed tier commit by its message · staging each tier gitlink
right after its commit.

**Memory entry points** — satisfying FR11 and FR8 with no parent commit or push
in flight.
[memory-entry-points.md](references/memory-entry-points.md)

- **D16** — a standalone, arg-driven memory-commit entry point
- **D20** — a push entry point the skill calls directly, with no trigger file

*Rejected:* triggering a memory commit through a parent commit · reimplementing
the sentinel, `push HEAD:live` and merge-state logic in a caller · a caller that
pre-writes the commit-message file.

**Install and the memory remote** — what one-time setup does and refuses.
[installation.md](references/installation.md)

- **D8** — remote creation requires explicit user confirmation
- **D25** — direct wiring refuses rather than appends after an existing `exec`
- **D45** — the sentinel replay is an allow-list, never `sh -c` on the tracked
  file

*Rejected:* a strictly non-empty initial commit · `gh repo create` as the only
remote-creation method · a separate `gitlore.memoryPath` config key · making the
memory push optional in v1 · replaying the sentinel as a shell command.

**Memory redirect** — [memory-redirect.md](references/memory-redirect.md)

- **D10** — the redirect is a launch-time `--settings` shim, not a project
  setting

*Rejected:* `autoMemoryDirectory` in project settings · the same key in global
`~/.claude/settings.json` · `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc` ·
an explicit `gitlore` launch command instead of shadowing `claude`.

**The session and its wrappers** — where the wrappers live and are anchored, and
what SessionStart says to whom.
[session.md](references/session.md)

- **D5** — wrapper scripts live in the git common dir, untracked
- **D11** — wrapper paths anchor at the git common dir, so linked worktrees work
- **D14** — user-facing SessionStart output goes on `systemMessage`
- **D21** — a mid-session plugin upgrade is a notice, not a self-healing config

*Rejected:* tracked hook scripts in the repo · a literal `.git/gitlore-<hook>`
wrapper path · a per-worktree wrapper anchor · a `WorktreeCreate` hook · a
version-less plugin pointer resolved at hook runtime · wrappers self-healing
from `CLAUDE_PLUGIN_ROOT`.

**Claude Code platform workarounds** — harness behaviours, each carrying the
empirical work that established it, which is why they stay whole.
[cc-platform.md](references/cc-platform.md)

- **D15** — an in-process-worktree memory-drift guard
- **D18** — active recall is a skill the agent runs itself: no hook, no state
- **D23** — the `Edit` weld defect is contained by a pair that computes the
  intended result, repairs, and reports its own obsolescence
- **D51** — a hook's output inside a subagent reaches that subagent alone, so
  its report is relayed through a marker

*Rejected:* hook-side injection of the bodies from a request file the agent
writes · a `PreToolUse` deny on the first durable write of an episode · leaving
a subagent's hook report to the subagent's own narration.

**Tiered memory** — D17 is the call; the subsystem's own decisions conclude in
the opening summary of each node: retrieval and routing (D26–D28, D32, D33) in
[tiered-memory.md](references/tiered-memory.md), composition (D29–D31, D34–D37)
in [index-composition.md](references/index-composition.md), the authoring-time
sync and the authoring guidance with its invocation (D38–D40, D47, D48) in
[index-authoring-sync.md](references/index-authoring-sync.md), and the tier
stores and merges (D42–D44) in [tier-stores.md](references/tier-stores.md).

- **D17** — FR15: nested tier submodules plus a structurally composed root index

*Rejected:* a flat merge-everything store · a content classifier routing each
new fact (tiered-memory.md) · propagating the root index down into the carriers
· recompose owning index-line presence · deleting a memory file when its pointer
line is removed · a `SessionStart` warning when a tier is mounted without a
paired guard plugin (index-composition.md) · frontmatter `description` as the
source of truth for the index one-liner · scoring an index hook against its
body, tf-idf style (index-authoring-sync.md) · an append-only constraint on
shared-tier indexes · a `merge` driver plus `.gitattributes` ·
`**/MEMORY.md merge=union` plus a dedup-by-path pass (tier-stores.md).

---

## Rejected Alternatives

Each is named on the *Rejected* line of its decision group above and argued in
the `## Rejected alternatives` section that closes that group's node. A decision
that was later inverted lives in the changelog, not here.
