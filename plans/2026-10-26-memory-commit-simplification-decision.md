# Draft — D70, the memory commit simplification

For review. Records my human partner's decision: the agent commits memory
itself, through `commit-memory.sh` with the approved summary on a quoted
heredoc, after the user approves that summary in conversation; no hook commits
authoring content and no git hook gates a memory commit. D58 (the commit is the
agent's own act) and D59 (SessionStart moves memory nowhere) are already
recorded and true, and are not part of this entry. The entry is recorded when
the code in section 5 is true.

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
- **D70** — the agent commits memory itself, with the approved summary as
  `commit-memory.sh -F -` on a quoted heredoc; no hook makes an authoring
  commit, no git hook gates one, and the summary travels with the call, never
  through a file the agent writes
```

*Rejected:* additions to the group's line:

```markdown
an intent file and a `PostToolBatch` hook as a fallback for a denied call · a
submodule `pre-commit` gate behind the conversational approval · a bare
`commit-memory.sh` retrying on an approval left on disk · the summary
transported through a well-known path in the parent working tree · unsetting
`GIT_AUTHOR_*` and `GIT_COMMITTER_*` before every store commit
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

> Arg-driven, `git commit`-style: `-m <summary>`, `-F <file>`, or `-F -`
> (stdin/heredoc), one of them required. A summary that is absent, empty or all
> whitespace is a usage error ahead of any store access. The script writes the
> summary to a temporary file, the same way `resolve.sh` carries a merge
> message, and that file is the `-F` operand of every commit the run makes — the
> tier commits and memory's own — and is removed on every exit. Guards (exit 0):
> not a gitlore repo / no memory submodule / submodule worktree absent / memory
> clean-and-synced. Dirty with the store or any mounted tier mid-merge → the
> stale-merge guard's directive (exit 1), ahead of everything else.

Decision paragraph, after D58:

> **D70 — The agent commits memory itself, with the summary passed in the call**
>
> The agent summarizes the pending changes, shows the summary, ends its turn,
> and once the user's reply approves it runs
> `bash "$(git config gitlore.commitCommand)" -F - <<'EOF'` with the summary as
> the heredoc body. That is the whole commit protocol. No hook commits authoring
> content: the `PostToolBatch` path that committed on a trigger file is gone,
> and so is the gate inside each store that admitted only commits carrying a
> sentinel.
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
> already refuses, and a leftover file reads as a pending approval. A temporary
> file per run carries the text and means nothing after the run (D70).
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

## 5. What becomes false, and what has to go

### Decisions removed from the index

- **D4** (file handshake; presence is approval) — inverts: nothing the agent
  writes is an approval signal. Its rejected items move per section 3.
- **D12** (submodule-side gate) — the hard gate retires; the orientation half
  moves into D70 (section 4).
- **D53** (report-only guard arms do not restamp) — no restamp exists.
- **D54** (failure-time restamp blessing a concurrent write) — no restamp
  exists. The residual it accepted on the success path (freshness read before
  the `add -A`) disappears with freshness; a write another session lands mid-run
  is committed under the summary, which is the case D54's last sentence already
  places outside what an approval speaks for.
- **D56** (batch retry judged by freshness) — no batch, no bare retry.

### Decision lines and node paragraphs edited

- `decisions.md` group "Memory entry points", D58 line — unchanged; its node
  paragraph's opening ("`commit-memory.sh` — directly, or through the trigger
  file `memory-commit-batch.sh` acts on — is the one commit path") drops the
  trigger clause.
- `memory-entry-points.md` D16 "Arg-driven, not file-driven" — keeps the
  `git commit`-shaped contract; loses "The message file stays purely the
  hook↔commit IPC handshake (D4)", the whole freshness / bare-invocation passage
  and "the mtime gate continues to protect the non-interactive trigger-file
  path". The approval rests on the caller's contract, full stop. D16's
  motivating paragraph ("a naked submodule commit is blocked by the D12 gate")
  loses the D12 clause.
- `memory-entry-points.md` D20 "Why the skill calls the script directly, unlike
  the trigger-file commit" — becomes: both entry points are called directly; the
  denial argument there is the one D70 now makes for the commit.
- `memory-entry-points.md` "Shared body" chain — drop "dirty/freshness gate",
  `rm <msgfile>` and the freshness-arm wording; the summary-request arm moves
  out of the sync into the script's usage error.
- `git-hooks.md` D50 — drop "the approval is restamped" from the index-file
  abort; delete the paragraph
  "**A failure keeps the approval, unless it prepared a merge.**"; in "A tier
  commit the run could not record…", "`memory-commit-batch.sh` promises a
  transparent retry" becomes "a retried commit would be refused for good". The
  D50 conclusion line stands.
- `git-hooks.md` header bullets and "Decisions — D46, D50, D53, D54" — drop
  D53/D54 and their two rejected paragraphs; title becomes "D46, D50".
- `commit-gate.md` — Mechanism section (intent file, four states, blank screen,
  merge outranks screen) is deleted whole; D4, D12, D56 sections and their
  rejected paragraphs go; D19's call-site paragraph is rewritten (open question
  5); what remains is D19, D22, D67.
- `commit-gate.md` D19, "`resolve.sh` reaches the clause through its callers" —
  falls if the sync's refusal arm goes (it is the one call site there).
- `docs/design.md:29-35` FR11 — "before the commit message file is written and
  the commit executes" becomes "before the commit executes".
- `docs/design.md:203-204` "the agent writes prose or an intent file" — still
  true for `add-tier`; `:235` "`PostToolBatch` acts on the two intent files"
  becomes "the add-tier intent file".
- `docs/references/configuration.md:34-40` IPC files — only
  `.claude/gitlore-add-tier` remains; `:60-65` "Commit message file" paragraph
  goes.
- `docs/references/session.md:296` — drop `memory-pre-commit` from the
  agent-vs-user branch list.
- `docs/references/tier-stores.md:38-50` — the "No recursing hook" argument
  loses its `memory-pre-commit` clauses; the driver-side recursion argument
  stands.
- `docs/references/memory-authoring-guidance.md:91-94` — the freshness sentence
  goes; the review-before-summary placement argument stands on the summary
  describing the commit.
- `docs/references/cc-platform.md:252-262` (D60) — "all six hooks" becomes five;
  the `memory-commit-batch.sh` consequence clause goes.
- `CLAUDE.md` (repo) "Memory and commits" — already describes the direct call.
  `memory/ddaanet/shared-claude.md` "Never `--no-verify`… the parent repo's
  pre-commit hook is the gitlore memory gate" has been false since D58; it is a
  shared tier, so propose, do not edit.

### Code and tests that go

- `scripts/cc-hooks/memory-commit-batch.sh`; its entry in `hooks/hooks.json:92`.
- `scripts/git-hooks/memory-pre-commit`, `scripts/emit-memory-gate.sh`, and its
  call at `scripts/cc-hooks/session-start.sh:201`.
- `scripts/lib/util.sh`: `gitlore_commit_trigger_file`,
  `gitlore_commit_msg_file`, `gitlore_commit_msg_freshness`;
  `gitlore_approval_present` becomes a check on the summary string (or is
  inlined).
- `scripts/lib/resolve-sync-memory.sh`: the freshness arm (`:33-56`), every
  `touch "$msgfile"` (15 across it and `resolve-sync-tiers.sh`), the restamp
  comment block (`:67-87`), `rm -f "$msgfile"` (`:247`); the function takes the
  message file as an argument.
- `GITLORE_MEMORY_COMMIT=1` at `resolve-sync-memory.sh:245`,
  `resolve-sync-tiers.sh:61`, `resolve.sh:70`, `resolve-adopt-report.sh:131`,
  `install/init-submodule.sh:81`, and the gate's own test.
- `scripts/commit-memory.sh`: bare mode and its usage line; the post-write
  approval screen becomes a pre-write usage check.
- Comment fixups naming the batch: `resolve-push.sh:28`,
  `util-config.sh:27,105`, `util-merge-state.sh:49`,
  `resolve-sync-tiers.sh:48,60`.
- `.gitignore:6-7`; `tests/helpers/fixtures.bash:199`.
- Tests deleted: `tests/cc_hook_memory_commit_batch.bats`,
  `tests/cc_hook_memory_commit_batch_merge.bats`,
  `tests/helpers/cc-hook-memory-commit-batch.bash`,
  `tests/git_hook_memory_pre_commit.bats`, `tests/emit_memory_gate.bats`,
  `tests/integration_memory_gate.bats`, `tests/commit_memory_retry.bats`
  (freshness retry), the freshness and trigger cases in `tests/lib_util.bats`,
  the `emit-memory-gate.sh` and `memory-pre-commit` cases in
  `tests/script_lib_lookup.bats`, the gate cases in
  `tests/tier_lockstep.bats:178-200`, `tests/plugin_distribution.bats:205-210`,
  `tests/index_sync_propagation.bats:376` comment.
- Tests rewritten to pass the summary with `-F`: every suite seeding the message
  file — `commit_memory.bats`, `commit_memory_approval.bats`,
  `commit_memory_compose_status.bats`, `commit_memory_reports.bats`,
  `integration_happy_path.bats`, `resolve_compose.bats`,
  `resolve_recovery_landed_commit.bats`, `helpers/resolve-recovery.bash`,
  `helpers/tier-fixtures.bash:97` (`approve`).
- Evals: `tests/evals/lib/finish-commit.sh`,
  `tests/evals/lib/asserts_commit.bats`, `tests/evals/asserts/memory-commit.sh`,
  `tests/evals/asserts/tier-write.sh` assert on the message file and the
  trigger; they assert on the memory log and the absence of an in-turn commit
  instead.
- New: a red test that a bare `commit-memory.sh` and an all-whitespace `-F -`
  each exit 2 with nothing committed; a test that no file is left under
  `.claude/` after a run, success or refusal.

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

> Once approved, commit the memory from the repo root, the approved summary as
> the heredoc body: `bash "$(git config gitlore.commitCommand)" -F - <<'EOF'`.

It verifies the resolved path is executable, as D16 asks of a caller, and keeps
its clause-file refusal unchanged. `with-commit` mode then commits memory before
the parent commit stages the pointer the script staged.

## 8. Open questions

My human partner's answers, 2026-10-26: 4, 6 and 7 take their defaults. 5: the
approval comes before the memory commit, as it does today; the difference is
that the memory commit is a step of the agent's normal commit workflow rather
than a hook's; the `SessionStart` orientation keeps naming the commit command
and the clause file rather than inlining the clause. 1–3 take their defaults.
The `handoff` brief of section 7 is in `/Users/david/code/handoff/inbox/`.

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
