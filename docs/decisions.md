# gitlore Design Decisions

The decisions index of the living design, [design.md](design.md): every decision
the project has taken, as a one-line conclusion, and every rejected alternative,
by name. This is the file to have in front of you when weighing a new decision —
a conclusion missing from here is one that gets re-litigated, silently. The
argument behind each conclusion — what was weighed, what was rejected, and why —
lives in the `docs/references/` node its group names, one hop away, and
`tools/check-docs-links.py` gates that every conclusion here has an argument
there and every argument there a conclusion here.

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

*Rejected:* `git commit-tree` plus `git update-ref` for the resolve merge · a
temporary worktree for resolve · `claude --print` for conflict resolution ·
single-agent resolve with a post-hoc context refresh.

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
- **D22** — the memory-hygiene checker is a repo-local gate, not shipped surface
- **D67** — the repo's own gate, test and dev tooling lives in `tools/`, not
  `scripts/`: `dist.include` lists `scripts` whole, so anything there ships, and
  `tools/` is not listed

*Rejected:* a per-file `dist.include` exclude or allowlist for the tooling ·
tooling left in `scripts/` with its docstrings fixed.

**Git hooks** — what `pre-push` does inside a parent git operation, and the
pointer invariant that rests on it.
[git-hooks.md](references/git-hooks.md)

- **D46** — a parent commit is never rewritten to re-pin memory
- **D50** — the commit path composes a dirty store before it commits; a pin
  refusal aborts, a compose problem in an index file the commit changes aborts,
  and every other compose refusal reports; a tier merely ahead of its pin is put
  back on it for `/gitlore:merge` to adopt, and a retry that skips that take
  commits — the residual is accepted, costing one later merge and no fact

*Rejected:* a tip amend to re-pin memory · a refusal that instructs the agent to
run compose · reporting an off-pin tier and committing through it · recognising
gitlore's own landed tier commit by its message · staging each tier gitlink
right after its commit · composing a clean store · reporting a non-empty
commit-path compose · leaving a tier whose adoption failed ahead of an unstaged
pin · a blanket refusal for every tier ahead of its pin · refusing the commit
while a tier's local `live` is ahead of its pin · adopting inside the pin guard
rather than directing to `/gitlore:merge`.

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

**Install** — what one-time setup does and refuses.
[installation.md](references/installation.md)

- **D25** — direct wiring refuses rather than appends after an existing `exec`
- **D45** — the sentinel replay is an allow-list, never `sh -c` on the tracked
  file

*Rejected:* a strictly non-empty initial commit · a separate
`gitlore.memoryPath` config key · replaying the sentinel as a shell command.

**The memory remote** — how it is created, and which url is recorded.
[memory-remote.md](references/memory-remote.md)

- **D8** — remote creation requires explicit user confirmation
- **D64** — the tracked `.gitmodules` records
  `https://github.com/<owner>/<repo>.git` for a GitHub ssh url, given or
  resolved, while the submodule's own remote keeps the url as given, so pushes
  stay on that transport
- **D65** — a confirmed-public parent with a confirmed-private memory or tier
  remote gets one stderr line, because a private repository anywhere in the
  chain aborts an anonymous recursive clone whatever the url form; visibility is
  never changed, and a visibility `gh` cannot read is silent

*Rejected:* `gh repo create` as the only remote-creation method · making the
memory push optional in v1 · recording the ssh url in `.gitmodules` · rewriting
the remote to https as well · rewriting an existing install's `.gitmodules` from
`SessionStart` or install · creating tiers public by default · refusing the
mount over visibility · a new flag or command for the visibility check · warning
on an unknown visibility.

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

**The hook wrappers** — where the wrappers live and how they are anchored.
[hook-wrappers.md](references/hook-wrappers.md)

- **D5** — wrapper scripts live in the git common dir, untracked
- **D11** — wrapper paths anchor at the git common dir, so linked worktrees work

*Rejected:* tracked hook scripts in the repo · a literal `.git/gitlore-<hook>`
wrapper path · a per-worktree wrapper anchor.

**The session** — what SessionStart says to whom, and why it moves memory
nowhere. [session.md](references/session.md)

- **D14** — user-facing SessionStart output goes on `systemMessage`
- **D59** — SessionStart moves memory nowhere; every advance is an explicit take
  or push

*Rejected:* a `WorktreeCreate` hook · the clean-only fast-forward at session
start.

**The plugin-upgrade notice** — what a session does when the plugin moves under
it. [plugin-upgrade-notice.md](references/plugin-upgrade-notice.md)

- **D21** — a mid-session plugin upgrade is a notice, not a self-healing config

*Rejected:* a version-less plugin pointer resolved at hook runtime · wrappers
self-healing from `CLAUDE_PLUGIN_ROOT` · a `PreCompact` registration of the
nudge reset · re-arming on every `SessionStart` source.

**Claude Code platform workarounds** — harness behaviours, each carrying the
empirical work that established it, which is why they stay whole.
[cc-platform.md](references/cc-platform.md)

- **D15** — an in-process-worktree memory-drift guard
- **D23** — the `Edit` weld defect is contained by a pair that computes the
  intended result, repairs, and reports its own obsolescence
- **D51** — a hook's output inside a subagent reaches that subagent alone, so
  its report is a write-once file keyed by session and agent, drained by a
  dedicated `PostToolBatch` hook
- **D60** — a `PostToolBatch` hook that dies reports on both channels and exits
  0; when it cannot report, it exits non-zero but never 2

*Rejected:* leaving a subagent's hook report to the subagent's own narration ·
one shared marker per agent that each reporting hook merges into · a drain
inside each reporting hook · claim-by-rename before reading · folding another
session's stranded reports at `SessionStart` · relaying in place of the
subagent's own emission · exit 1 passthrough alone · a fixed message with no
capture · per-site `|| exit 0` · a wrapper script in `hooks.json` · rewriting
every non-zero status to 1 · a mount report with a line saying composition did
not run, via `gitlore_compose_and_report` under `if !`.

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
tier merges (D44) in [tier-conflicts.md](references/tier-conflicts.md), the
repair of an arriving index and the merged-index gate (D52) in
[tier-arrival-repair.md](references/tier-arrival-repair.md), and the edit that
removes a tier pointer (D66) in
[index-drift-fixes.md](references/index-drift-fixes.md).

- **D17** — FR15: nested tier submodules plus a structurally composed root index

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
(memory-authoring-guidance.md) · a down projection that skips a root line whose
file the tier does not hold · writing root and staging the pair atomically
(tier-stores.md) · an append-only constraint on shared-tier indexes · a `merge`
driver plus `.gitattributes` · `**/MEMORY.md merge=union` plus a dedup-by-path
pass (tier-conflicts.md) · a message fix alone for an unadoptable arrival · a
push that tolerates the defect · a `--no-ff` merge of the arrival onto the pin ·
an agent-driven repair through the memory-merger · a mechanical repair of a
merge synthesis · repairing only when every problem names the carrier · a
continuation that commits a defective merged index uncomposed · a scratch
directory in the tier's gitdir · a sweep of stale `gitlore-repair.*` directories
on the next repair (tier-arrival-repair.md) · leaving the pointer-removal rule
to recall from D36 (index-drift-fixes.md) · listing the sibling repositories'
plugins at each gate instead of holding a list · the route alone, with no
inventory · an index line for the inventory fact · a general memory reviewer
(memory-authoring-guidance.md) · keeping the add-tier intent file and hook with
a canned commit added · the agent running `gitlore-commit` with a canned mount
summary · a rubric-graded mount summary · the add-tier intent as `--options` or
JSON arguments (tiered-memory.md).

**Design history** — how the design's changelog is kept, and where a retired
decision goes. [design-history.md](references/design-history.md)

- **D72** — git history is the design's changelog: no dated records, a
  design-significant change carries its why in the commit body or the node, and
  an inverted or retired decision is deleted from the index and its node with
  the why in the deleting commit; its number is not reused

*Rejected:* keeping the existing records frozen while writing no new ones ·
splitting `changelog.md` by period to pass the size check · a "retired
decisions" section in `decisions.md`.

**Artifact size** — the 400-line cap over everything a reader takes in at one
go, and the check that gates it.
[artifact-size.md](references/artifact-size.md)

- **D55** — the 400-line cap is a context budget, so it binds scripts, hooks and
  suites as well as `docs/`

*Rejected:* raising the cap · gating tokens instead of lines · leaving the rule
outside `docs/` a convention with no checker · a separate checker script for the
source tree · counting only shell files, not python.

---

## Rejected Alternatives

Each is named on the *Rejected* line of its decision group above and argued in
the `## Rejected alternatives` section that closes that group's node. A decision
that is later inverted or retired is deleted from the index and its node, with
its why in the deleting commit (D72).
