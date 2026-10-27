# Draft — D70, the memory commit simplification

For review. Records my human partner's decision: the agent commits memory
itself, through `gitlore-commit-memory` (the plugin `bin/` name for
`commit-memory.sh`) with the approved summary on a quoted heredoc, after the
user approves that summary in conversation; no hook commits authoring content
and no git hook gates a memory commit. The `gitlore.commitCommand`,
`gitlore.pushCommand` and `gitlore.mergeCommand` discovery keys retire in favour
of the three `bin/` names. D58 (the commit is the agent's own act) and D59
(SessionStart moves memory nowhere) are already recorded and true, and are not
part of this entry. The entry is recorded when the code in section 5 is true.

## 1. Number

**D70.** `**D<n>**` in `docs/decisions.md` stops at D68, but D69 exists: it is
cited inline in the tiered-memory group (`decisions.md:219`) and argued in
`docs/references/memory-authoring-guidance.md:127`. Nothing under `docs/` or
`plans/` uses D70.

## 2. Two places the brief's premise does not hold

**`pre-push` does create store commits.** `gitlore_push_stores`
(`scripts/lib/resolve-push.sh:140`, `:165`, `:307`) runs the take inside the
push whenever a tier's `live` is ahead of its HEAD or a store is behind its
remote. The take commits: `gitlore_commit_tier_bookkeeping`
(`scripts/lib/resolve-adopt-report.sh:131`) runs `git commit` in the memory
store (D49's canned bookkeeping commit), and `gitlore_adopt_commit_repair`
(`scripts/lib/resolve-adopt.sh:234`) builds a tier commit with `commit-tree`
(D52's arrival repair). Both are FR11's stated exemptions — no authoring content
— so the entry scopes "no hook commits" to *authoring* commits, the term FR11
uses, and open question 1 asks whether the take-in-push goes too.

**`handoff` is already half stranded.** Its `with-commit` mode
(`/Users/david/code/handoff/scripts/_checkpoint_lib.py:155`, identical in the
installed 0.18.0) writes the message file and tells the agent "the commit that
lands these changes carries the memory": that was the parent `pre-commit`, which
D58 retired, so today that mode leaves memory uncommitted with nothing said. Its
`without-commit` mode writes the summary and the trigger, which this entry
retires. Section 7 has the replacement.

## 3. `docs/decisions.md`

**Group: "Memory entry points"**, beside D16, D20 and D58, because the entry
decides the shape of the one commit path those three describe. The "commit gate"
group keeps D19, D22 and D67 and is retitled (open question 6).

Conclusion line:

```markdown
- **D70** — the agent commits memory itself through the `gitlore:commit` skill,
  the approved summary on `gitlore-commit-memory`'s stdin as a quoted heredoc,
  one `== <store> ==` section per store that changed; no hook
  makes an authoring commit, no git hook gates one, and the summary travels
  with the call, never through a file; callers reach the three entry points by the
  plugin `bin/` names `gitlore-commit-memory`, `gitlore-push-memory` and
  `gitlore-merge-memory`, and the `gitlore.*Command` keys retire
```

*Rejected:* additions to the group's line:

```markdown
an intent file and a `PostToolBatch` hook as a fallback for a denied call · a
submodule `pre-commit` gate behind the conversational approval · a bare
`commit-memory.sh` retrying on an approval left on disk · the summary
transported through a well-known path in the parent working tree · unsetting
`GIT_AUTHOR_*` and `GIT_COMMITTER_*` before every store commit · keeping the
`gitlore.*Command` discovery keys alongside the `bin/` names
```

The commit-gate group's existing *Rejected:* items move with them:
`a Stop hook to generate the commit message`,
`PostToolUse on every memory Write/Edit` and
`an interactive prompt inside the pre-commit hook` are rejected alternatives to
a hook-driven commit and stay true under D70, so they move to the entry-points
group; `an in-session diff dump for commit review` and
`a PreToolUse hook constraining the agent's git operations` move likewise. The
D56 items (exit-code protocol, parsing the refusal text, deleting the message
file, the `-ef` guard, freshness checked in the hook) and the D53/D54 items (a
per-arm return code, a `touch -r` snapshot) argue about a mechanism that no
longer exists, and leave with their decisions for the changelog.

**Lines removed** (inverted or retired, so to the changelog per the index's
closing rule): **D4**, **D12**, **D53**, **D54**, **D56**. Section 5 gives each
one's reason.

## 4. Node text — `docs/references/memory-entry-points.md`

Mechanism, replacing the bare-invocation sentence block of "Memory Commit Entry
Point":

> The summary is read from stdin, the script's only input. A terminal on stdin,
> or a summary that is empty or all whitespace, is a usage error pointing at
> `/gitlore:commit`, ahead of any store access. Every summary is one
> `== <store> ==` section per store with changes, a single store included, and
> each section — `memory` for root, a tier's mount name for a tier — is its
> store's message, piped verbatim to that store's `git commit` on stdin, tiers
> before root. Text outside a section, a store with changes and no section, a
> section for a store with nothing to commit or not mounted, or a store named
> twice is refused the same way, nothing committed. Root changes confined to
> `MEMORY.md` need no section, since an index line moves with its fact: alone
> they get a plain commit of their own whose canned message names the tiers
> whose index lines it captures (`Index lines from <tier>, …`), distinct from
> the merge path's bookkeeping message, and beside a `memory` section they ride
> in root's own commit. No message file exists at any point. Guards (exit 0):
> not a gitlore repo / no memory submodule / submodule worktree absent / memory
> clean-and-synced. Dirty with the store or any mounted tier mid-merge → the
> stale-merge guard's directive (exit 1), ahead of everything else.

Decision paragraph, after D58:

> **D70 — The agent commits memory itself, with the summary passed in the call**
>
> The `gitlore:commit` skill carries the protocol and the summary format: the
> agent summarizes the pending changes, shows the summary, ends its turn, and
> once the user's reply approves it runs `gitlore-commit-memory <<'EOF'` from
> the repo root with the approved summary, verbatim, as the heredoc body. That
> is the whole commit protocol. One message per store keeps a private store's
> paragraphs out of a shared tier's log, which a single summary committed into
> every store did not. No hook commits authoring content: the `PostToolBatch`
> path that committed on a trigger file is gone, and so is the gate inside each
> store that admitted only commits carrying a sentinel.
>
> **The approval lives in the conversation, so the commit goes where the
> conversation is.** D58 moved the commit out of the parent `pre-commit` because
> a hook has no one to converse with. The trigger file kept a second hook in the
> loop for one reason: a denied Bash call might strand a summary the user had
> already approved. It does not strand it. The summary is in the transcript the
> agent holds, so a denial costs one turn — the same call again, or behind a `!`
> prefix — which is the cost D20 accepts for the push. Against that, the hook
> path carried a message file whose presence meant approval, an mtime freshness
> verdict deciding whether a retry still held it, a restamp after every failure
> that prepared no merge, and four outcome arms read off the store after the run
> (D4, D53, D54, D56). All of it existed so that an approval could outlive the
> call that used it. With the summary passed in the call, nothing outlives the
> call, and a retry is the agent passing the summary again — re-approved in
> conversation when the store has moved since.
>
> **No gate inside the store.** The submodule `pre-commit` admitted any commit
> carrying `GITLORE_MEMORY_COMMIT=1` and refused the rest. It never saw an
> approval: an agent can run `commit-memory.sh` with a summary nobody approved
> as easily as it can run `git commit`, and the 2026-10-11 eval (4 of 5 runs
> committed in the same turn as the request) is that case, which the gate
> admitted. What it did block is a direct `git commit` in the store, which the
> `SessionStart` orientation already forbids by role. Its cost was a sentinel on
> every commit site gitlore owns, a wrapper emitted into every store's hooks
> dir, a `gitlore.hooksDir` mirrored into every store's config, and a stale
> wrapper's "relaunch" hint whenever the plugin cache moved. So the orientation
> is the only control between the agent and an authoring commit, and the entry
> says so rather than implying a backstop: the text, its acts-only shape and its
> closing rule — a request to commit memory is not approval of a summary the
> user has not seen — are argued below and pinned by
> `tests/cc_hook_session_start.bats`. A human committing inside the store meets
> nothing, as with any git repository they own.
>
> **What a hook may still commit.** `pre-push` runs the take when a store is
> behind its remote or a tier's `live` is ahead of its HEAD, and the take can
> land D49's canned bookkeeping commit and D52's arrival repair. Neither authors
> content — FR11 names both as its exemptions — so neither is what this decision
> removes. No hook path commits anything else: `SessionStart` moves nothing
> (D59), `add-tier-batch.sh` commits only the seed of a tier it is creating, in
> a scratch repository before any clone mounts it, and the index hooks write
> files without committing them.
>
> **Callers reach the entry points by name, not by a config key.** The plugin
> ships `bin/gitlore-commit-memory`, `bin/gitlore-push-memory` and
> `bin/gitlore-merge-memory`, each a thin `exec` of `scripts/commit-memory.sh`,
> `scripts/push-memory.sh` or `scripts/merge-memory.sh` resolved from the file's
> own location. Claude Code puts each enabled plugin's `bin/` on the Bash tool's
> PATH: a session's PATH holds
> `~/.claude/plugins/cache/ddaanet/autodrive-handoff/0.18.0/bin`, a versioned
> cache path only Claude Code knows, and subagents inherit it. The
> `gitlore.commitCommand`, `gitlore.pushCommand` and `gitlore.mergeCommand` keys
> existed for exactly those callers — the `handoff` plugin and the agent's own
> Bash, which have no `CLAUDE_PLUGIN_ROOT` (D16's "Discovery via
> `gitlore.commitCommand`", the push "Discovery" paragraph, and D20's skill
> body, which makes its one call through `gitlore.pushCommand`). gitlore's own
> hooks have the variable and never read the keys, and they keep calling
> `$PLUGIN_ROOT/scripts/…`: a hook that calls a bare `bin/` name works in
> dogfood, where the shim sets PATH on the whole process, and may fail once
> released. So the keys retire with their seeding in
> `scripts/install/write-settings.sh`, their re-pin at `SessionStart`, and D16's
> advice that a caller check the resolved path is executable. Staleness is
> unchanged: PATH is fixed at session start and the key was re-pinned at session
> start, so a plugin update mid-session leaves either one naming the old cache
> path until the next session. A disabled plugin makes the name "command not
> found"; whether gitlore manages memory in a repo is still read from the memory
> submodule registration in `.gitmodules` (FR12), never from the command's
> existence. The in-repo dogfood session gets the same names:
> `plugin-dev/bin/claude` appends `<root>/dist/plugin/bin` to PATH
> unconditionally, and `just dogfood` ships `bin/` there once `dist.include`
> lists it.

The orientation argument moves here from D12, as the paragraph after "No gate
inside the store", lightly re-framed: the orientation paragraph of
`commit-gate.md` (the bullet beginning
"**Orientation (removes the friction of hitting the hard gate).**") minus its
first clause and its last sentence ("The gate's own `$CLAUDECODE`-branched
output remains the fallback…"). Its sentence "Since D58 … this text is the only
gate between the agent and the commit" stays true and gains the eval evidence it
already carries.

Rejected alternatives paragraphs, appended to the node's section:

> **An intent file and a `PostToolBatch` hook as a fallback for a denied call.**
> The fallback was for a summary stranded by a denial, and a denial strands
> nothing: the summary is in the transcript, and re-running costs one turn. It
> carried a message file as the approval signal, a freshness verdict, failure
> restamps and four outcome arms, each added to keep a disk approval honest
> across retries the direct call never makes (D70).
>
> **A submodule `pre-commit` gate behind the conversational approval.** It
> distinguishes a sentinel, not an approval, so it admits the unapproved commit
> the eval measured and refuses only the direct `git commit` the orientation
> already forbids. It costs a sentinel at every commit site, a wrapper and a
> mirrored config key in every store, and stale-wrapper noise after each plugin
> upgrade (D70).
>
> **A bare `commit-memory.sh` retrying on an approval left on disk.** An
> approval the caller did not just pass is exactly what the freshness machinery
> existed to judge; with no hook caller, the only remaining caller holds the
> summary and can pass it (D70).
>
> **The summary transported through a well-known path in the parent working
> tree.** A named path invites a caller to pre-write it, the alternative D16
> already refuses, and a leftover file reads as a pending approval. The text
> stays in the process and reaches each commit on its stdin (D70).
>
> **Unsetting `GIT_AUTHOR_*` and `GIT_COMMITTER_*` before every store commit.**
> The leak it guards came from a store commit made inside the parent's
> `pre-commit`, because `git commit` exports `GIT_AUTHOR_NAME`, `_EMAIL` and
> `_DATE` to its hooks and `--local-env-vars` does not list them. D58 removed
> that hook. The one git hook left, `pre-push`, can still commit through the
> take, but `git push` exports none of those variables to it (probed on git
> 2.47.3: a `pre-commit` saw all three, a `pre-push` none), and the
> `PostToolBatch` hooks run under Claude Code with no git operation around them.
> An identity exported in the user's own shell is their identity, not a leak.
> The scrub guards a state nothing produces (D70).
>
> **Keeping the `gitlore.*Command` discovery keys alongside the `bin/` names.**
> Every caller the keys served runs in the Bash tool, where the names already
> resolve, and the keys go stale exactly when PATH does. Kept, they are a second
> discovery path to the same script, with a seed at install, a re-pin every
> session, an executable check every caller is told to make, and tests for each.
> The one caller they reach that PATH does not is a human in a terminal outside
> Claude Code, and the commit there is not the human's path: it is the agent's
> act (D58), and push and merge are skills (D20, D43).

## 5. What becomes false, and what has to go

Every decision, node paragraph, script and test the entry makes false — the
commit-path removals and the retired discovery keys — is listed with file, line
and what it needs in
[the removals list](2026-10-26-memory-commit-simplification-removals.md).

## 6. G3

Moot, on the evidence in the last rejected paragraph of section 4: the leak
required a store commit made under a parent `git commit`; D58 removed the only
such hook; the hook that can still commit, `pre-push`, receives no author or
committer variables from `git push`; Claude Code hooks run outside any git
operation. G3 is listed under the D70 *Rejected:* line so the scrub is not
re-proposed. The identity-rewrite plan's §6 G3 bullet can then point at D70.

## 7. `handoff`

Stranded in both modes once this lands (section 2). The replacement, for a brief
to `/Users/david/code/handoff` and nothing more: `memory_directive` drops
`msgfile`, `trigger` and the mode split, and after the shared approval text
says, in both modes:

> Commit memory through `/gitlore:commit`.

The skill carries the summary format, the approval turn and the call, so
`handoff` resolves no key, checks no path, and loses its clause-file refusal
with the clause file. `with-commit` mode then commits memory before the parent
commit stages the pointer the script staged.

## 8. Open questions

My human partner's answers, 2026-10-26: 4, 6 and 7 take their defaults. 5: the
approval comes before the memory commit, as it does today; the difference is
that the memory commit is a step of the agent's normal commit workflow rather
than a hook's; the `SessionStart` orientation keeps naming the commit command
and the clause file rather than inlining the clause. 1–3 take their defaults.
The `handoff` brief of section 7 is in `/Users/david/code/handoff/inbox/` and
names `gitlore-commit-memory`.

Later answers, 2026-10-27, superseding the call syntax in the next paragraph and
the answer to question 5 above: the summary is read from stdin only (`-m`, `-F`
and bare mode go), and no message file exists, temporary or not; every summary
carries one `== <store> ==` section per changed store, a single store included,
each committed in its own store — a headerless form would commit wherever the
changes are, landing a summary meant for root in a shared tier when only the
tier changed; the summary format and protocol live in a `gitlore:commit` skill
that the script's usage and error messages point at, and the clause file, its
key and its reader retire.

My human partner's answer, 2026-10-27: the three entry points ship as plugin
`bin/` names — `gitlore-commit-memory`, `gitlore-push-memory`,
`gitlore-merge-memory` — and the `gitlore.*Command` keys retire with their
seeding, their re-pin and D16's executable-path advice; the agent's commit is
`gitlore-commit-memory -F - <<'EOF'` from the repo root. Section 4 carries the
grounds. D20's denial recovery re-runs the call behind a `!` prefix, and
`!`-mode Bash has the plugin `bin/` on PATH: `echo "$PATH"` behind `!` in the
dogfood session (CC 2.1.310, 2026-10-27) listed `dist/plugin/bin` and
`autodrive-handoff/0.18.0/bin`.

1. **Does the take inside `pre-push` stay?** It is the one hook path left that
   commits (bookkeeping, arrival repair). Default: **stays** — no authoring
   content, FR11 exempts both, and removing it reverts D49's attempt → take →
   attempt push.
2. **Message file: temporary file, or keep the `.claude/` path as internal
   transport?** Default: **`mktemp`** — no path to pre-write, nothing left to
   mean approval, nothing to gitignore.
3. **Landing records** (`gitlore_stage_landed_tiers`, `gitlore-tier-landing`)
   were justified by the batch's promised retry, but a killed direct run leaves
   the same off-pin tier and the agent's retry meets the same refusal. Default:
   **keep**; only D50's wording changes.
4. **Emitted wrappers in installed clones.** Every memory store and tier holds a
   `pre-commit` wrapper and a mirrored `gitlore.hooksDir`. With
   `memory-pre-commit` gone, the wrapper fires on every commit gitlore makes and
   prints "hooks dir is stale … relaunch". Default: **`SessionStart` removes a
   wrapper byte-identical to `gitlore_emit_hook_wrapper … memory-pre-commit`
   output and unsets the mirrored key**, D58's `wire-direct.sh` precedent; any
   other `pre-commit` there is left alone. This adds surface, so it is a fork.
5. **Where the approval clause reaches the agent.** Both in-gitlore emitters of
   `gitlore_memory_approval_clause` go (the batch hook, the sync's refusal), so
   nothing in-session delivers D48's review directive or the body spec. Default:
   **append the clause to the `SessionStart` orientation** (≈1.3 KB per session)
   and to `commit-memory.sh`'s usage error; D19's key and file stay for
   `handoff`.
6. **The commit-gate group after D4, D12, D56 leave.** Default:
   **retitle it "Approval wording and repo gates"**, keep `commit-gate.md` as
   the node file so inbound links hold, and open it on D19, D22, D67.
7. **Bare `commit-memory.sh` from an old caller.** A caller written against the
   bare form may still call it so. Default: **usage error naming `-F -`**, no
   compatibility mode — D16's contract is the published boundary, and the
   message is the migration.
