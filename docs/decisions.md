# gitlore Design Decisions

The decisions index of the living design, [design.md](design.md): every decision
the project has taken, as a one-line conclusion, and every rejected alternative,
by name. This is the file to have in front of you when weighing a new decision —
a conclusion missing from here is one that gets re-litigated, silently. The
argument behind each conclusion — what was weighed, what was rejected, and why —
lives in the `docs/references/` node its group names, one hop away, and
`tools/check-docs-links.py` gates that every conclusion here has an argument
there and every argument there a conclusion here.

Two clusters are delegated, because each is read only while changing its own
subsystem. The index keeps one entry naming the decisions and their nodes; for
the install-time and platform surfaces each node opens with the conclusion lines
and the rejected alternatives by name, in this file's form, and for tiered
memory the nodes conclude in their openings while the rejected names stay here.

---

## Design Decisions

**Branch model** — what `live` is, how a store sits on it, and which side of a
merge is first parent. [branch-model.md](references/branch-model.md)

- **D1** — `live` is the memory trunk, decoupled from the parent's default
  branch
- **D6** — merge direction: the more-authoritative side is the first parent
- **D41** — detached at `live`: one branch model, one commit path, every store

*Rejected:* `live` as a working branch.

**Merge and resolve** — the divergence path.
[merge-and-resolve.md](references/merge-and-resolve.md)

- **D3** — ordinary checkout during resolve, not git plumbing
- **D7** — scripts decide, the agent handles language
- **D9** — a sub-agent synthesizes the merge (requires the experimental flag)
- **D13** — a lock-contention retry wrapper guards mutating memory git calls
- **D24** — a directive that names a sub-agent carries its own authorization
- **D49** — canned unprompted merge commits; takes commit their bookkeeping
- **D75** — a push publishes each store as soon as it is ready: a tier repaired
  or merged inside a push goes to its remote even when a later tier or memory
  then fails, because races are not routine but must be expected, and an
  unpushed resolution is remerged at every remote update instead of
  fast-forwarded; pushing it is what puts the store back on `live`.
  `/gitlore:merge` is for incoming and publishes nothing
  ([publishing-divergence.md](references/publishing-divergence.md))
- **D76** — a module's position report hints `/gitlore:push` for any divergence,
  a `HEAD` forked from local `live` included, and `/gitlore:merge` only when the
  take is a fast-forward plus the canned bookkeeping commit: a divergence makes
  the fast-forward impossible, a tax on every later upstream update, and the
  push prepares the merge and publishes it
  ([publishing-divergence.md](references/publishing-divergence.md))
- **D79** — an unresolvable pin, a recorded commit its repository lacks, is an
  integrity error at every level: nothing composes or is recorded over it; a
  tier gitlink is published by the checkout that recorded it or reverted whole
  by `/gitlore:resolve`, and the parent's pin on memory has no command
  ([unresolvable-pin.md](references/unresolvable-pin.md))
- **D81** — `resolve.sh abort-merge` restores a prepared merge under git's
  `reset --merge` contract, aimed at the pending commit
  ([merge-state-recovery.md](references/merge-state-recovery.md))

*Rejected:* `git commit-tree` plus `git update-ref` for the resolve merge · a
temporary worktree for resolve · `claude --print` for conflict resolution ·
single-agent resolve with a post-hoc context refresh · holding a repaired tier
back until memory can record it · keeping a tier merge landed inside the
pre-push hook unpublished · publishing from `/gitlore:merge` · hinting
`/gitlore:merge` for a divergence · hinting `/gitlore:resolve` for a `HEAD`
forked from local `live` · a fallback base for the compose · a reset of memory's
`live` past the commit that recorded a lost pin · reverting only the gitlink
line · a command or a url change for the parent's pin · a healthy report over an
unresolvable pin · a hand-rolled keep, drop or refuse list for the abort.

**History rewrites** — what a rewritten store publishes, and what a clone on the
old history does. [history-rewrites.md](references/history-rewrites.md)

- **D61** — a rewritten store publishes a rewrite record: an append-only
  `gitlore/rewrites` branch whose tree is a format version and one flat map of
  every commit id the rewrites changed; the old history stays on an archive
  branch gitlore never fetches
- **D62** — a divergence whose local side holds a recorded old commit is
  refused, naming the crossing script; nothing repairs it automatically
- **D63** — a damaged record is rebuilt from scratch from the commit-maps at
  hand: the record branch is deleted on the remote and each commit-map is
  recorded again, oldest rewrite first; nothing salvages it in place

*Rejected:* no guard · an automatic crossing at the yield · matching commits
without a map · a path-keyed map · an external cache · a record force-pushed as
a single commit · the old tip as a parent of the record · guarding the parent
repository · an in-place salvage of a damaged record · a leased replacement of a
damaged record.

**Approval wording and repo gates** — the one approval wording, and the repo's
own gate and tooling. [commit-gate.md](references/commit-gate.md)

- **D19** — one canonical approval wording, held in the `gitlore:commit` skill
  and nowhere else
- **D82** — the `gitlore:commit` skill triggers on a request to commit memory,
  not on a store that is edited and uncommitted
- **D22** — the memory-hygiene checker is a repo-local gate, not shipped surface
- **D67** — the repo's own gate, test and dev tooling lives in `tools/`, not
  `scripts/`: `dist.include` lists `scripts` whole, so anything there ships, and
  `tools/` is not listed

*Rejected:* a per-file `dist.include` exclude or allowlist for the tooling ·
tooling left in `scripts/` with its docstrings fixed · a state condition as the
commit skill's trigger.

**Git hooks** — what `pre-push` does inside a parent git operation, and the
pointer invariant that rests on it.
[git-hooks.md](references/git-hooks.md)

- **D46** — a parent commit is never rewritten to re-pin memory
- **D50** — the commit path writes no index: a store whose indexes a compose
  pass would change aborts, naming them and `gitlore-compose`; so does a tier
  off its pin (every mounted tier; one ahead of it naming the take) and a
  compose problem in an index file the commit changes, while every other compose
  refusal reports

*Rejected:* a tip amend to re-pin memory · composing at the commit · committing
through a tier ahead of its pin.

**Memory entry points** — satisfying FR11 and FR8 with no parent commit or push
in flight.
[memory-entry-points.md](references/memory-entry-points.md)

- **D16** — a standalone memory-commit entry point, called with the approved
  summary
- **D20** — a push entry point the skill calls directly, with no trigger file

*Rejected:* triggering a memory commit through a parent commit · reimplementing
the sentinel, `push HEAD:live` and merge-state logic in a caller · a caller that
pre-writes the commit-message file · a `Stop` hook to generate the commit
message · `PostToolUse` on every memory `Write`/`Edit` · an interactive prompt
inside the `pre-commit` hook · an in-session diff dump for commit review.

**Who commits memory** — the agent's own act, never a parent-commit side effect
or a hook's.
[memory-commit-ownership.md](references/memory-commit-ownership.md)

- **D58** — a memory commit is the agent's own act, never a side effect of a
  parent commit: `commit-memory.sh` is the one commit path and stages the moved
  gitlink; the parent `pre-commit` hook and its nudge are retired
- **D70** — the agent commits memory itself through the `gitlore:commit` skill,
  the approved summary on `gitlore-commit`'s stdin as a quoted heredoc, one
  `== <store> ==` section per store that changed; no hook makes an authoring
  commit, no git hook gates one, and the summary travels with the call, never
  through a file; callers reach the three entry points by the plugin `bin/`
  names `gitlore-commit`, `gitlore-push` and `gitlore-merge`, and the
  `gitlore.*Command` keys retire

*Rejected:* the hook standing down on a missing approval · a `PreToolUse` hook
constraining the agent's git operations · an intent file and a `PostToolBatch`
hook as a fallback for a denied call · a submodule `pre-commit` gate behind the
conversational approval · a bare `commit-memory.sh` retrying on an approval left
on disk · the summary transported through a well-known path in the parent
working tree · unsetting `GIT_AUTHOR_*` and `GIT_COMMITTER_*` before every store
commit · keeping the `gitlore.*Command` discovery keys alongside the `bin/`
names.

**Install-time and platform surfaces** — read while changing install, the memory
remote, the hook wrappers, the upgrade notice or a Claude Code workaround, not
while reasoning about memory itself. Each node opens with its conclusions and
names its rejected alternatives: install (D25, D45) in
[installation.md](references/installation.md), the memory remote (D8, D64, D65,
D80) in [memory-remote.md](references/memory-remote.md), the hook wrappers (D5,
D11) in [hook-wrappers.md](references/hook-wrappers.md), the plugin-upgrade
notice (D21) in [plugin-upgrade-notice.md](references/plugin-upgrade-notice.md),
and the Claude Code platform workarounds (D15, D23, D51, D60) in
[cc-platform.md](references/cc-platform.md).

**Memory redirect** — [memory-redirect.md](references/memory-redirect.md)

- **D10** — the redirect is a launch-time `--settings` shim, not a project
  setting
- **D68** — the shim injects only the memory submodule's own path, refusing
  cheapest first: a control character (the path unshown); an absolute path; a
  `..` or `.` component; a `.git` or `.gitlore` component, or a `.claude`
  component not followed directly by `memory`, all case-insensitive; a nearest
  existing ancestor that does not resolve under the physical root, or whose
  resolved path plus the part not yet created is the root or breaks the same
  control-directory rule; a path the index does not hold only as mode-160000
  entries, at any stage. A refusal is one stderr line, then claude launches
  unredirected

*Rejected:* `autoMemoryDirectory` in project settings · the same key in global
`~/.claude/settings.json` · `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc` ·
an explicit `gitlore` launch command instead of shadowing `claude` ·
canonicalizing the memory directory alone · a `*..*` glob for traversal · a
silent passthrough on refusal · patching a consumer's generated copy ·
containment under the root as the whole test · refusing every `.claude`
component · requiring exactly one index entry.

**The session** — what SessionStart says to whom, and why it moves memory
nowhere. [session.md](references/session.md)

- **D14** — user-facing SessionStart output goes on `systemMessage`
- **D59** — SessionStart moves no module; every advance is an explicit take or
  push
- **D74** — compose only where the edit happens: `PostToolBatch`, the mount and
  an explicit take are the only writers of an index, `gitlore-compose` clears
  what no batch will, and the commit aborts on a pending compose; SessionStart
  reports and writes no index, because anything `PostToolBatch` did not compose
  is assumed to be an exterior change and failing on it beats silently fixing it

*Rejected:* a `WorktreeCreate` hook · the clean-only fast-forward at session
start · moving a tier at `SessionStart` · composing at `SessionStart` ·
composing at the commit · splitting the compose pass for a read-only caller.

**Active recall** — why recall is a skill the agent runs itself, not a hook.
[active-recall.md](references/active-recall.md)

- **D18** — active recall is a skill the agent runs itself: no hook, no state

*Rejected:* hook-side injection of the bodies from a request file the agent
writes · a `PreToolUse` deny on the first durable write of an episode.

**Tiered memory** — D17 is the call; the subsystem's own decisions conclude in
the opening summary of each node: retrieval and routing (D26–D28, D32, D33, D71)
in [tiered-memory.md](references/tiered-memory.md), composition (D29–D31,
D36–D37) in [index-composition.md](references/index-composition.md), what
composition reports (D34, D35, D57) in
[composition-reports.md](references/composition-reports.md), the authoring-time
sync (D38–D40) in [index-authoring-sync.md](references/index-authoring-sync.md),
the authoring guidance with its invocation and its owner inventory (D47, D48,
D69) in [memory-authoring-guidance.md](references/memory-authoring-guidance.md),
the tier stores (D42, D43) in [tier-stores.md](references/tier-stores.md), the
take order and compose (D77, D78) in
[take-and-compose.md](references/take-and-compose.md), the tier merges (D44) in
[tier-conflicts.md](references/tier-conflicts.md), the repair of an arriving
index and the merged-index gate (D52) in
[tier-arrival-repair.md](references/tier-arrival-repair.md), and the edit that
removes a tier pointer (D66) in
[index-drift-fixes.md](references/index-drift-fixes.md).

- **D17** — FR15: nested tier submodules plus a structurally composed root
  index; a tier's gitlink is what root last composed against

*Rejected:* a flat merge-everything store · a content classifier routing each
new fact (tiered-memory.md) · propagating the root index down into the carriers
· a `SessionStart` warning when a tier is mounted without a paired guard plugin
(index-composition.md) · recompose owning index-line presence · deleting a
memory file when its pointer line is removed · the mount's size as a percentage
of the advisory budget · sharing the edit-time advisory's marker kind with the
mount, or giving the mount one of its own (composition-reports.md) · frontmatter
`description` as the source of truth for the index one-liner · scoring an index
hook against its body, tf-idf style (index-authoring-sync.md) · a `PreToolUse`
deny on writes under `memory/` · an index-size trigger for the audit · carrying
the index lines' routing surface into the descriptions
(memory-authoring-guidance.md) · visiting root first with a per-tier bookkeeping
commit · keeping the per-tier root write, staged pair and walk-back · a marker
recording a killed take · an overwrite compose-up · a base read from `HEAD` ·
the pass composing a tier ahead of its pin up and staging the gitlinks it merged
· a dirty gate per caller of the yield · recording in the merge state which tier
commits the continuation has offered root as a chunk · composing in the prepare
· an adoption step in `/gitlore:merge` or `gitlore-compose --up`
(take-and-compose.md) · an append-only constraint on shared-tier indexes · a
`merge` driver plus `.gitattributes` · `**/MEMORY.md merge=union` plus a
dedup-by-path pass (tier-conflicts.md) · a message fix alone for an unadoptable
arrival · a push that tolerates the defect · a `--no-ff` merge of the arrival
onto the pin · an agent-driven repair through the memory-merger · a mechanical
repair of a merge synthesis · repairing only when every problem names the
carrier · a continuation that commits a defective merged index uncomposed · a
scratch directory in the tier's gitdir · a sweep of stale `gitlore-repair.*`
directories on the next repair (tier-arrival-repair.md) · leaving the
pointer-removal rule to recall from D36 (index-drift-fixes.md) · listing the
sibling repositories' plugins at each gate instead of holding a list · the route
alone, with no inventory · an index line for the inventory fact · a general
memory reviewer (memory-authoring-guidance.md) · keeping the add-tier intent
file and hook with a canned commit added · the agent running `gitlore-commit`
with a canned mount summary · a rubric-graded mount summary · the add-tier
intent as `--options` or JSON arguments (tiered-memory.md).

**Design history** — how the design's changelog is kept, and where a retired
decision goes. [design-history.md](references/design-history.md)

- **D72** — git history is the design's changelog: no dated records, a
  design-significant change carries its why in the commit body or the node, and
  an inverted or retired decision is deleted from the index and its node with
  the why in the deleting commit; its number is not reused

*Rejected:* keeping the existing records frozen while writing no new ones ·
splitting `changelog.md` by period to pass the size check · a "retired
decisions" section in `decisions.md`.

**Artifact size** — the byte cap over everything a reader takes in at one go,
and the toolkit check that gates it.
[artifact-size.md](references/artifact-size.md)

- **D73** — the cap is 20000 bytes a file, 10000 for a `SKILL.md`, checked by
  the toolkit's `check-size` over every file git does not ignore; it binds
  scripts, hooks and suites as well as `docs/`

*Rejected:* raising the cap · gating tokens instead of bytes · leaving the rule
a convention with no checker · a separate checker script for the source tree ·
counting only shell files, not python · keeping the line check beside the byte
check.

---

## Rejected Alternatives

Each is named on the *Rejected* line of its decision group above, or of its
delegated node's opening for the install-time and platform surfaces, and argued
in the node. A decision that is later inverted or retired is deleted from the
index and its node, with its why in the deleting commit (D72).
