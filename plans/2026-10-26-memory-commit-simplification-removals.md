# D70 — what becomes false, and what has to go

Companion to
[the D70 draft](2026-10-26-memory-commit-simplification-decision.md): every
decision, node paragraph, script and test the entry makes false, with file and
line, and what each needs. Section numbers below are the draft's.

### Decisions removed from the index

- **D4** (file handshake; presence is approval) — inverts: nothing the agent
  writes is an approval signal. Its rejected items move per the draft's section
  3.
- **D12** (submodule-side gate) — the hard gate retires; the orientation half
  moves into D70 (the draft's section 4).
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
- Tests rewritten to pipe the summary on stdin: every suite seeding the message
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
- New: a red test that an empty and an all-whitespace stdin each exit 2 with
  nothing committed; a test that no file is left under `.claude/` after a run,
  success or refusal.

### The discovery keys and the `bin/` names

Grep: `commitCommand\|pushCommand\|mergeCommand` across `docs/`, `scripts/`,
`hooks/`, `skills/`, `tests/` and `CLAUDE.md`. The `docs/changelog/` hits are
history and stay. The `precommitCommand` substring hits
(`memory-entry-points.md:258,286`, `installation.md:63`,
`write-settings.sh:9,12`) are D58's cleanup and stay. `memory-pre-commit:18`
goes with its file above. `hooks/` and the repo `CLAUDE.md` have no hit.

New:

- `bin/gitlore-commit-memory`, `bin/gitlore-push-memory`,
  `bin/gitlore-merge-memory`, mode 755, each an `exec` of its script under
  `scripts/`, resolved from the file's own location (`CLAUDE_PLUGIN_ROOT` is
  unset in agent Bash).
- `dist.include` gains `bin`; without it neither `just dogfood` nor a release
  ships the directory.
- `tests/plugin_distribution.bats`: each `bin/gitlore-*` exists, is `-x`, and
  reaches its script (run it by path in a non-gitlore directory and assert the
  script's guard exit).

Scripts:

- `scripts/install/write-settings.sh:35-37` — the three seeds go.
- `scripts/cc-hooks/session-start.sh:112-114` — the three re-pins go; `:77`
  orientation text names the `gitlore:commit` skill in place of
  `bash "$(git config gitlore.commitCommand)" -F -` and the clause file.
- `scripts/commit-memory.sh:12`, `scripts/push-memory.sh:12`,
  `scripts/merge-memory.sh:14-15` — "Discover this script via `git config …`"
  becomes "Callers run it as `gitlore-…-memory`, the plugin `bin/` name".

Skills:

- `skills/push/SKILL.md:25` → `gitlore-push-memory`; `:73` → `/gitlore:commit`.
- `skills/merge/SKILL.md:21` → `gitlore-merge-memory`.
- `skills/memory-writing/SKILL.md:240` — "through `gitlore.commitCommand`"
  becomes "through `gitlore-commit-memory`".
- `skills/resolve/SKILL.md:13` — drops the `PostToolBatch` hook as a commit
  path; `:93` — the bare retry is false under D70: the retry passes the summary
  again, re-approved when the merge brought content it did not cover.

Docs:

- `docs/references/memory-entry-points.md:1` header and `:12-14` bullets gain
  D70; `:51-53` "Discovery" names the `bin/` command; `:93-94` push "Discovery"
  likewise; `:134` the skill's one call is `gitlore-push-memory`; `:200-212` D16
  "Discovery via `gitlore.commitCommand`" is replaced by the D70 discovery
  paragraph (the executable-path advice goes, the FR12 activation sentence
  stays); `:299` "callers resolve it via `gitlore.commitCommand`" becomes
  "callers run `gitlore-commit-memory`".
- `docs/references/merge-and-resolve.md:141` → `gitlore-merge-memory`.
- `docs/references/workflows.md:17`, `:50`, `:65` — each "through the
  `gitlore.*Command` key" becomes the `bin/` name; `:17-19` also loses the
  trigger-file alternative.
- `docs/references/commit-gate.md:163` (orientation, moving into D70) → the
  `gitlore:commit` skill; `:233-239` "Discovery mirrors D16's
  `gitlore.commitCommand`" goes with the clause file and its key: the skill body
  is the summary format's only copy, and D19's call-site paragraphs follow.
- "Five keys" becomes one (`gitlore.hooksDir`):
  `docs/references/configuration.md:24-31` (and its "each consumer verifies the
  resolved path" clause narrows to it), `docs/references/session.md:74-76`,
  `docs/design.md:177-179`, `docs/references/plugin-upgrade-notice.md:31-32`.

Tests:

- `tests/write_settings.bats:16-34` — the three seeding cases go; `:37` "seeds
  gitlore.hooksDir alongside commitCommand" is renamed.
- `tests/cc_hook_session_start.bats:77-80` — the four re-pin assertions go (the
  clause-file key's with the others); `:178-179` assert the orientation names
  the `gitlore:commit` skill.
- `tests/cc_hook_session_start_report.bats:161`,
  `tests/cc_hook_session_start_relay.bats:143` — assert the bin name.
- `tests/script_lib_lookup.bats:7` comment and `:179` — the assertion runs
  `bin/gitlore-commit-memory` by path instead of reading the key.
- `tests/plugin_distribution.bats:144-146`, `:159` — assert the skill names
  `gitlore-push-memory` / `gitlore-merge-memory`; the comment's "never a
  hardcoded plugin path" reason stays.
- `tests/integration_happy_path.bats:29` — bats runs outside Claude Code, so
  PATH holds no plugin `bin/`: call `"$PLUGIN_ROOT/bin/gitlore-commit-memory"`
  by path, which also exercises the exec. Any other suite that would rely on the
  name resolving does the same.
- `tests/evals/README.md:66` — the bin name, and the trigger-file alternative
  goes.
