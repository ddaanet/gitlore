# Batch 7 — merge-state problem lines, the rootless-store notice, a spaced pin-guard case

All three items are done and uncommitted. `just format-docs` and
`python3 scripts/check-docs-links.py` both ran clean at the end.

---

## Item 1 — the merged-index gate's problem lines survive a clear or compact

### What I verified before building on it

- The merge state file is **JSON**, built by `jq -n` in
  `gitlore_write_merge_state` and `gitlore_write_merge_marker`
  (`scripts/lib/resolve.sh`), written through `$statefile.tmp` and `mv`.
  Every reader goes through `jq` with a `// ""` or `// []` default, except
  `jq -r .flavor`, which reads a field both writers always emit. Adding a field
  therefore cannot break a file written by the previous version, and a line's
  bytes round-trip through JSON rather than through a shell split.
- Readers/writers, grepped: `scripts/resolve.sh` (`load_continuation_state` —
  `.store`, `.flavor`, `.publish`), `scripts/lib/resolve.sh`
  (`gitlore_guard_stale_merge_state`, `gitlore_restore_staged_merge`,
  `gitlore_pending_commit`, `gitlore_complete_merge_state`,
  `gitlore_emit_merge_directive`), `scripts/lib/index-compose.sh`
  (`gitlore_compose_check_pins`, presence only),
  `scripts/lib/util.sh` (`gitlore_merge_state_file`, `gitlore_clear_merge_state`).
- `gitlore_emit_merge_directive` has three call sites: the
  `stale-with-merge-head` arm of the guard, `gitlore_restore_staged_merge`, and
  `gitlore_yield_merge`. The first two re-emit an **existing** state file — the
  clear/compact case; the third writes a fresh one, so no stale lines can leak
  into a new merge.
- The gate itself is `compose_merged_indexes` in `scripts/resolve.sh:111`: on
  `gitlore_compose_up` rc 1 it runs `gitlore_compose_problems_in` against the
  merged index and, on a hit, prints and `exit 1`s.

### Files changed

- `/Users/david/code/gitlore/scripts/lib/resolve.sh` — `gitlore_emit_merge_directive`
  reads `(.index_problems // [])[]` and emits a block between the state-file path
  and the dispatch paragraph; new `gitlore_record_merge_index_problems`, placed
  directly after its reader.
- `/Users/david/code/gitlore/scripts/resolve.sh` — `compose_merged_indexes`
  records the check's verdict on **every** run of the gate, the empty answer
  included, then refuses as before.
- `/Users/david/code/gitlore/skills/resolve/SKILL.md` — the directive shape in
  **Parse directive** gains the optional problem block; **Dispatch** passes the
  lines through; the resume-the-same-sub-agent workaround is cut to the stop rule.
- `/Users/david/code/gitlore/agents/memory-merger.md` — `index_problems` added to
  the state file's field list with what the sub-agent owes it.
- `/Users/david/code/gitlore/docs/references/merge-state-recovery.md` — the node
  that documents the state file: a new paragraph on the field, why the empty
  answer is recorded, and that an older file reads as carrying none.
- `/Users/david/code/gitlore/docs/references/tier-arrival-repair.md` — the D52
  passage now says the lines are recorded and re-emitted, not merely that a later
  gate re-emits the directive.
- `/Users/david/code/gitlore/tests/resolve_compose.bats` — three tests.

### Red evidence

| test | failing assertion at red |
| --- | --- |
| `a re-emitted directive carries the merged-index problem lines` | `[[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]` on the re-emitted directive (`tests/resolve_compose.bats:227`) |
| `a problem line holding spaces, quotes and a leading dash re-emits byte for byte` | `printf '%s\n' "$stderr" \| grep -qxF -- "gitlore:   $problem"` (`:248`), with `problem` = `memory/ddaanet/MEMORY.md: duplicate pointer path -a "q" b.md` |
| `a merged index that passes the check re-emits without the lines an earlier run recorded` | born green — mutation below |

Mutation for the third (hand-applied; `mutate-and-run.sh` refuses a subject with
uncommitted edits, and `scripts/lib/resolve.sh` was mid-edit): replace
`json='[]'` in `gitlore_record_merge_index_problems` with `return 0`, so the
empty answer is not recorded. **KILLED** — the test failed on
`[[ "$stderr" != *"duplicate pointer path t.md"* ]]`. The subject was restored
from a byte-for-byte backup and `git diff` re-checked.

### Design choices

- **The field carries the check's verdict, not just its failures.** A merge can
  stay prepared for a reason outside the merged files (a refused commit, a
  message that would not build). Without recording the empty answer, a directive
  emitted after such a run would brief the next sub-agent to fix text a later
  synthesis had already cleared. That is the third test.
- **Recorded at the gate, not at preparation time.** The gate runs long after
  `gitlore_write_merge_state`, against a store the merger has rewritten, so the
  field is edited into the existing file with `jq … > tmp && mv` — the same
  shape every other write of this file uses.
- **No retry cap**, as directed. The skill keeps the stop rule it already had:
  a re-synthesis drawing the same problem line stops and relays to the user.
- **The merger agent reads the field itself.** Not in the brief, but the agent
  definition enumerates the state file's fields, and a stale enumeration is how
  a fresh sub-agent ends up not knowing what the directive just told its parent.

### Not done

No decision line was added to `docs/decisions.md`: this is mechanism inside D52's
gate, not a new decision with rejected alternatives of its own. No
`docs/changelog.md` entry either — outside this brief, and batch 4 owns the
records.

---

## Item 2 — a store with no root `MEMORY.md`

### What I verified before building on it

- The check is skipped at `[ -f "$root" ] || return 0`, at the top of both
  `gitlore_compose` and `gitlore_compose_up` (`scripts/lib/index-compose.sh`).
  `gitlore_compose` returns 0 with empty output there, so
  `gitlore_compose_and_report` cannot tell that case from "nothing to do".
- Both `PostToolBatch` hooks bailed even earlier: `[ -e "$index" ] || exit 0` in
  `scripts/cc-hooks/index-compose.sh` and `scripts/cc-hooks/index-sync-post.sh`.
  Nothing tool-driven said anything about a rootless store.
- `gitlore_compose_check_pins` is called **directly** by the commit path
  (`scripts/lib/resolve.sh:1117`), so rule 7 still runs on a rootless store. What
  is off is `gitlore_compose`'s own body: the two projections, rules 1–4 and the
  weld rule, plus the merge continuation's merged-index gate.
- `scripts/cc-hooks/session-start.sh:228` already writes the `# Memory Index`
  scaffold back and reports it. So a store reaching a batch without an index lost
  the file *inside* the session — which is why the notice belongs on the batch
  hook and why it can safely report rather than repair.
- The once-per-episode mechanism already exists: `_gitlore_nudge_file` /
  `_gitlore_nudge_reset` in `scripts/lib/index-sync.sh`, keyed by session id in
  the memory gitdir, re-armed at `SessionStart` and `PreCompact` by
  `scripts/cc-hooks/nudge-reset.sh`.

### Files changed

- `/Users/david/code/gitlore/scripts/cc-hooks/index-compose.sh` — the
  `[ -e "$index" ] || exit 0` guard becomes an `if/else`: the rootless arm sets
  `GITLORE_COMPOSE_SYSMSG`/`GITLORE_COMPOSE_CTX` and falls through to the hook's
  existing relay-and-emit tail; the compose arm is the previous body, indented.
  The `session` parse moved above the branch, which is the only reordering.
- `/Users/david/code/gitlore/scripts/lib/index-sync.sh` —
  `gitlore_rootless_nudge_file` / `gitlore_rootless_nudge_reset`.
- `/Users/david/code/gitlore/scripts/cc-hooks/nudge-reset.sh` — re-arms it.
- `/Users/david/code/gitlore/scripts/install/init-submodule.sh` — the scaffold
  is now written whenever the seeded store has no `MEMORY.md`, migration branch
  included (see the install defect below).
- `/Users/david/code/gitlore/docs/references/index-composition.md` — a paragraph
  under D31 stating what a rootless store turns off and how the notice is keyed.
- `/Users/david/code/gitlore/docs/references/tier-arrival-repair.md` — the
  "runs no index check" sentence now points at that paragraph.
- `/Users/david/code/gitlore/docs/references/installation.md` — step 7 restated:
  copy, then scaffold if the store has none; step 16's announcement wording
  follows.
- `/Users/david/code/gitlore/tests/cc_hook_index_compose.bats`,
  `/Users/david/code/gitlore/tests/install_run.bats` — five tests.

### Red evidence

| test | failing assertion at red |
| --- | --- |
| `a store with no root index says composition and the index checks are off` | `[[ "$output" == *"no root MEMORY.md"* ]]` — the hook emitted nothing at all |
| `the no-root-index notice fires once per session` | same assertion, first `feed` |
| `a subagent's no-root-index notice is staged for the parent` | same assertion |
| `install scaffolds the root index when the migrated auto-memory carried none` | `grep -qx '# Memory Index' memory/MEMORY.md` → `No such file or directory` |
| `a compaction re-arms the no-root-index notice` | born green — mutation below |

Two born-green assertions, both proved by hand mutation (the subjects were
mid-edit):

- **Re-arm.** Delete `gitlore_rootless_nudge_reset "$mempath" "$session"` from
  `nudge-reset.sh`. **KILLED** — the post-reset `feed` emitted nothing.
- **Reported, never repaired** (`[ ! -e memory/MEMORY.md ]`). Insert
  `printf '# Memory Index\n' > "$index"` into the rootless arm. **KILLED**.

Both subjects restored from byte-for-byte backups, verified with `git diff`.

### The install defect — real, reproduced, fixed

`/gitlore:install`'s copy-existing-auto-memory branch **could** produce a rootless
store. `scripts/install/init-submodule.sh` gated the copy on "the dir exists, is
non-empty, and is not a migration stub" and treated the scaffold as the *else*.
An auto-memory dir holding fact files but no `MEMORY.md` — a session interrupted
before Claude Code wrote the index, or one whose index was deleted — passes that
gate, and `cp -R` brings no index. The initial commit then records a store with
no root index. The comment above the branch had anticipated only the empty-dir
case.

Reproduction (the new test, `tests/install_run.bats`):

```
src=~/.claude/projects/<encoded-repo-path>/memory
mkdir -p "$src" && printf 'fact\n' > "$src/user_role.md"   # no MEMORY.md
/gitlore:install            # or: bash scripts/install/run.sh memory "echo precommit"
# before the fix: memory/MEMORY.md does not exist, and HEAD:MEMORY.md is absent
```

The fix is the small one the brief allowed: the copy no longer owns the `else`,
and a single `if [ ! -f "$mempath/MEMORY.md" ]` writes the scaffold afterwards.
A migration that brought its own index keeps it — pinned by the pre-existing
`install migrates pre-existing CC auto-memory at the mangled path` test, which
still passes with its migrated `MEMORY.md` intact.

### Design choices

- **The hook, not the library.** `gitlore_compose`'s stdout is the composed-file
  report its callers parse; it has no channel for a notice, and changing its
  return code would move the contract for the commit path's D50 arms. The hook
  owns `systemMessage` + `additionalContext` and already has the relay.
- **Through the existing tail, not a second emitter.** Setting the two
  `GITLORE_COMPOSE_*` variables means the rootless notice inherits the relay
  write (D51) for free — which matters, because the marker is keyed by *session*,
  so a subagent firing the notice would otherwise spend the session's one telling
  where nobody else reads it. That is the third test.
- **Report, never repair.** A `MEMORY.md` the hook wrote would enter the store
  outside the approval gate. `SessionStart` is the one place that scaffolds,
  because what it writes rides the next FR11 commit under review.
- **Paths spelled relative** (`memory/MEMORY.md`), matching every sibling notice
  in this hook and in `session-start.sh`; the hooks `cd` to the project root.

---

## Item 3 — a spaced-path case for the pin guard's return-to-pin branch

### What I verified before building on it

The branch is in `gitlore_compose_check_pins`
(`scripts/lib/index-compose.sh:521`), the arm where a tier is ahead of its pin,
clean, and its local `live` contains `HEAD`. Reading it:

- Its **success** message has no `git` command in it at all — it ends
  `… it is back on the pin, so none of them is lost. Run /gitlore:merge …`.
  The `git -C "<abs>"` command the brief describes is in the **failure**
  sub-arm of the same branch (`… could not be returned to the pin … Return it
  with \`git -C "$abs" checkout --detach $pinned\``).
- Every caller passes a **relative** `mempath` (`gitlore_compose "$mempath"`,
  with `gitlore_memory_path` returning the `.gitmodules` path), so `$tierpath`
  is `memory/<tier>` and carries no space. A spaced *repository* path reaches
  this branch at exactly one point: the `abs=$(CDPATH='' cd -- "$tierpath" &&
  pwd)` that the printed command carries.

So the brief's two halves live in different arms, and I added one test for each
rather than one test asserting something the success arm does not emit.

### Files changed

`/Users/david/code/gitlore/tests/index_compose.bats` — a `reroot_spaced` helper
(the shape `tests/merge_memory.bats` already uses) and two tests.

### Evidence

- `a tier ahead of its pin is returned to it under a project path holding a space`
  — the whole branch under a spaced root: HEAD back on the pin, `live` still
  holding the commits, the worktree carrier following, the store clean, and the
  report's own wording. **Born green, and it has no discriminating whitespace
  mutation**: I tried `s/cd -- "$tierpath" && pwd/cd -- $tierpath && pwd/`
  through `scripts/mutate-and-run.sh` and it **SURVIVED**, because `$tierpath` is
  relative and spaceless by construction. It stands as a characterization that
  the branch is reached and completes under a spaced root, and I am reporting it
  as exactly that rather than as pinned behaviour.
- `a spaced tier that cannot be returned to its pin prints a command that runs verbatim`
  — the arm that hands the return to a human. It extracts the backticked command
  from the report, drops the `git` stub, and runs it with `(cd / && eval "$cmd")`
  from an unrelated directory, then asserts HEAD reached the pin. **Born green,
  KILLED by mutation**:

  ```
  scripts/mutate-and-run.sh scripts/lib/index-compose.sh \
    's/git -C \\"\$abs\\" checkout --detach \$pinned/git -C \$abs checkout --detach \$pinned/g' \
    tests/index_compose.bats 'spaced tier that cannot'
  ```

  → KILLED (`fatal: cannot change to '/tmp/claude-1000/gitlore'`). The existing
  unspaced test asserts those quotes *textually*; this one asserts the command
  runs.

**No whitespace defect was found in this branch**, so no production code changed
for item 3.

---

## Suites run (all foreground, one at a time)

Every suite that sources a changed script, grepped for the script and function
names, plus the four the brief named:

| suite | result |
| --- | --- |
| `tests/resolve_compose.bats` | 29 passed |
| `tests/resolve.bats` | 8 passed |
| `tests/resolve_recovery.bats` | 23 passed |
| `tests/resolve_both_flavors.bats` | 4 passed |
| `tests/resolve_merge_local.bats` | 4 passed |
| `tests/resolve_merge_remote.bats` | 3 passed |
| `tests/resolve_merge_briefing.bats` | 8 passed |
| `tests/commit_memory.bats` | 38 passed |
| `tests/git_hook_pre_commit.bats` | 21 passed |
| `tests/pre_push_hook.bats` | 9 passed |
| `tests/push_memory.bats` | 12 passed |
| `tests/push_behind_vs_diverged.bats` | 21 passed |
| `tests/push_rejection_discriminator.bats` | 9 passed |
| `tests/merge_memory.bats` | 42 passed |
| `tests/tier_divergence.bats` | 20 passed |
| `tests/cc_hook_index_compose.bats` | 32 passed |
| `tests/cc_hook_add_tier.bats` | 12 passed |
| `tests/cc_hook_plugin_upgrade.bats` | 12 passed |
| `tests/cc_hook_session_start.bats` | 25 passed |
| `tests/cc_hook_post_tool_use.bats` | 11 passed |
| `tests/index_sync.bats` | 87 passed |
| `tests/index_merge.bats` | 20 passed |
| `tests/index_compose.bats` | 90 passed |
| `tests/install_run.bats` | 26 passed |
| `tests/install_remote.bats` | 12 passed |
| `tests/lib_util.bats` | 24 passed |
| `tests/plugin_distribution.bats` | 15 passed |
| `tests/lint_shell.bats` | 3 passed |
| `tests/check_docs_links.bats` | 43 passed (re-run after `just format-docs`) |
| `tests/bsd_portability.bats` | 3 passed |

0 failed anywhere. `just format-docs` reflowed 5 issues in 3 files (my own doc
edits); `python3 scripts/check-docs-links.py` reports 54 decisions, 121 files,
zero findings in every category.

## Lint

`bash scripts/lint-shell.sh` is clean. Two findings came up on the new bats code
and are handled rather than ignored: `SC2164` fixed with `cd … || return 1`, and
`SC2317` on the `git` stub suppressed inline with the reason (`unset -f git`
later in the test is what makes shellcheck read the body as dead).

## State

Everything is uncommitted; nothing under `memory/` or `.claude/` was touched, no
branch was created or switched, and no `git checkout --`/`stash`/`restore` ran on
a file I did not edit. Sixteen files modified, no new tracked files.
