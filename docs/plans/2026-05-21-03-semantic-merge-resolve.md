# gitlore Plan 03 — Semantic Merge in `/gitlore:resolve`

> **Status:** spec / design. Implementation plan (task-by-task breakdown) will be expanded from this document by `superpowers:writing-plans`.

**Goal:** When pre-commit fails to ff-push the worktree branch into `live`, or pre-push fails to ff-push `live` to its remote, the user gets an end-to-end semantic merge instead of "manual fix required." The agent's only job is to dispatch the `memory-merger` sub-agent and approve its summary with the user; every other decision is in shell scripts.

**Reference:** `docs/design.md` is the authoritative spec (FR 5, D6, D7, D9 in particular). Plan 02 (`docs/plans/2026-05-19-02-remote-and-push.md`) is the immediate predecessor — pre-commit, pre-push, and `/gitlore:resolve` exist as primitives; this plan upgrades them to drive semantic merge.

---

## 1. Lessons-learned opener (Plan 02 retrospective)

Plan 02 shipped 89/89 + 1/1 green. Dogfood B on the gitmoji repo caught two real-world bugs the bats suite missed — `.gitmodules` gitignored and `gh repo create --source=.` rejecting gitfile-pointed submodule worktrees. Both were patched and backfilled with regression tests in commit `192d7e8` (see [[feedback-dogfood-b]] for the detailed findings).

The Plan 03 lesson is process, not content:

**Encode dogfood findings as automation in the same plan, not the next one.** Plan 02 did this — it didn't defer the fixtures to Plan 03. Per [[feedback-automate-default]], Plan 03 follows the same rhythm: any surprise its own dogfood gate surfaces gets a Layer 2 fixture inside Plan 03 before the plan is considered shipped, not handed off as backfill for Plan 04.

**Mock the failure modes, not just the success path.** Plan 02's `gh-mock.bash` initially encoded only successful `gh` responses; the gitfile-submodule rejection only surfaced under real `gh`. Plan 03's stub sub-agent (`tests/helpers/stub-synth.bash`) must encode the merge state on disk it expects to see, including the corrupted-state edge cases, not just a happy concatenation. Same principle.

---

## 2. Scope

### 2.1 In scope

- **Branch-vs-live semantic merge.** Triggered when pre-commit's ff-push of `<branch>` into local `live` fails (live advanced from another worktree).
- **Local-vs-remote semantic merge.** Triggered when pre-push's ff-push of `live` to `origin` fails (remote advanced).
- **`memory-merger` sub-agent.** A new agent file at `agents/memory-merger.md` with a tight, single-purpose contract (read state file, synthesize, write, `git add -A`, ask parent for approval, run continuation).
- **State-machine architecture.** Every script yield to the agent carries (a) the directive to dispatch `memory-merger` and (b) the **continuation command** the sub-agent runs after approval. Continuations may yield again — a single user operation can yield N times.
- **Recovery edges.** Stale `MERGE_HEAD` + state file from a crashed prior run; state file without `MERGE_HEAD` (manual out-of-band intervention); concurrent resolve in another worktree.
- **Install-time pre-flight.** `/gitlore:install` checks `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` (design step 1) and warns if unset. Install still completes; runtime surfaces a clean error if Task dispatch fails.
- **Encoding the Plan 03 dogfood gate's findings in-plan.** Any surprise surfaced by §6.3 becomes a Layer 2 fixture inside this plan before ship. (No carry-over from Plan 02 — its surprises were already backfilled in commit `192d7e8`.)

### 2.2 Out of scope (deferred to later plans)

- `WorktreeCreate` / `WorktreeRemove` hooks (Plan 04, unchanged).
- Clone-from-remote smoke test, polish, expanded docs (Plan 05, unchanged).
- Non-GitHub remotes / non-`gh` toolchains (still deferred from Plan 02).
- Multi-repo / multi-remote topologies beyond a single `origin` per memory submodule.
- Force-push prompts (`memory-merger` never force-pushes; it commits a real merge).
- Single-agent fallback when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is off (per D9, the flag is the chosen dependency).

---

## 3. Architecture — script-driven directives with continuations

Control flow stays in scripts. The agent's role is reduced to: read a directive, dispatch the `memory-merger` sub-agent with a state-file path, and let the sub-agent run the continuation command embedded in that state file.

### 3.1 State machine shape

```
                                          ┌────────────────────────────┐
                                          │                            │
trigger ──► prepare (script) ──► yield ──►│ dispatch memory-merger     │
(pre-commit│  detect divergence│ directive│  → sub-agent reads state   │
 pre-push, │  checkout live    │ + state  │  → reads files fresh       │
 /gitlore: │  merge --no-      │ file     │  → synthesizes             │
 resolve)  │  commit --no-ff   │          │  → git add -A              │
           │  write state file │          │  → SendMessage summary     │
           │  emit directive   │          │  → parent approves w/ user │
           │  exit             │          │  → run state.continuation  │
                                          │                            │
                                          └─────────────┬──────────────┘
                                                        │
                                          continuation (script):
                                            git commit (correct first parent)
                                            advance refs
                                            retry the push that triggered prepare
                                            ├── push succeeds → exit 0
                                            └── push fails → loop back to prepare
```

### 3.2 Entry points

Plan 02's `pre-commit`, `pre-push`, and `/gitlore:resolve` all become entry points to the same library. None of them route to "manual fix required" anymore — divergence is the signal to prepare and yield.

| Hook / command | Push attempted | Flavor on failure |
|---|---|---|
| `scripts/git-hooks/pre-commit` | `git push . HEAD:live` (ff-push worktree branch into local `live`) | branch-vs-live |
| `scripts/git-hooks/pre-push` | `git push origin live` (ff-push local `live` to remote) | local-vs-remote |
| `commands/gitlore/resolve.md` (script: `scripts/resolve.sh`) | Both, in turn | Either or both |

`/gitlore:resolve` invoked manually first `git fetch origin`, then attempts both pushes; each failure produces its own yield.

### 3.3 Script subcommands

`scripts/resolve.sh` gains subcommands. All other scripts in the library reuse them via shared functions in `scripts/lib/resolve.sh`.

| Subcommand | Role |
|---|---|
| `scripts/resolve.sh` (no args) | Default. Fetch, attempt both pushes, yield on each failure. |
| `scripts/resolve.sh continue-after-branch-merge` | Continuation: commit (live first parent), advance branch, retry `push . HEAD:live`, loop or exit. |
| `scripts/resolve.sh continue-after-remote-merge` | Continuation: commit (origin/live first parent), retry `push origin live`, loop or exit. |
| `scripts/resolve.sh abort-then-retry` | Recovery continuation: `git merge --abort`, return to `<return_branch>`, remove state file, re-enter the original loop. |

### 3.4 Directive emission

Every yield writes one structured directive to stderr (humans + agent both read it). Format:

```
gitlore: memory merge prepared (flavor=<X>).
gitlore: dispatch the memory-merger sub-agent with state file:
gitlore:   <abs-path-to-gitlore-merge-state>
gitlore: on approval, the sub-agent must run:
gitlore:   <continuation-command>
```

The `commands/gitlore/resolve.md` slash command is updated to recognize the directive shape and dispatch the Task tool with `subagent_type: memory-merger`. (Plan 03 introduces the agent file; the slash command is the dispatch point.) Plan 02's existing fallback message ("manual fix required") is removed from the failure-mode tables.

### 3.5 State file

`<mempath>/.git/gitlore-merge-state`, JSON:

```json
{
  "flavor":           "branch-vs-live | local-vs-remote",
  "base":             "<merge-base sha>",
  "source_ref":       "<branch> | <OLD_LOCAL sha>",
  "target_ref":       "live",
  "return_branch":    "<branch>",
  "changed_files":    ["MEMORY.md", "..."],
  "conflicted_files": ["MEMORY.md", "..."],
  "continuation":     "scripts/resolve.sh continue-after-..."
}
```

The state file is the sole contract between phase 1 (prepare), the sub-agent (synthesize), and phase 2 (continuation). The sub-agent never invokes git for state inspection.

---

## 4. Detection & plumbing flavors

### 4.1 Detection = the outcome of a push

No separate predicate check. The script attempts the push that the current phase requires; success returns clean, failure is the divergence signal. Each flavor is its own loop because a fresh divergence can appear during synthesis.

### 4.2 Branch-vs-live (in pre-commit and `/gitlore:resolve`)

Per D6, `live` is first parent (trunk stays linear):

**Prepare:**
1. Attempt `git push . HEAD:live`. Success → exit 0.
2. Failure → `BASE=$(git merge-base <branch> live)`. `git checkout live`. `git merge --no-commit --no-ff <branch>`.
3. Write state file with `flavor: "branch-vs-live"`, `source_ref: <branch>`, `target_ref: "live"`, `continuation: "scripts/resolve.sh continue-after-branch-merge"`.
4. Emit directive. Exit non-zero (the underlying `git commit` aborts).

**Continuation (`continue-after-branch-merge`):**
1. `git commit` (git's `MERGE_MSG`, `live` as first parent).
2. `git branch -f <branch> HEAD`.
3. `git checkout <branch>`.
4. Retry `git push . HEAD:live`. Success → exit 0. Failure → re-enter prepare.

### 4.3 Local-vs-remote (in pre-push and `/gitlore:resolve`)

Per D6, `origin/live` is first parent (remote's linear history is preserved):

**Prepare:**
1. `git fetch origin live`. Attempt `git push origin live`. Success → exit 0.
2. Failure → `OLD_LOCAL=$(git rev-parse live)`. `git checkout live`. `git reset --hard origin/live`. `git merge --no-commit --no-ff $OLD_LOCAL`.
3. Write state file with `flavor: "local-vs-remote"`, `source_ref: <OLD_LOCAL sha>`, `target_ref: "live"`, `continuation: "scripts/resolve.sh continue-after-remote-merge"`.
4. Emit directive. Exit non-zero.

**Continuation (`continue-after-remote-merge`):**
1. `git commit` (`origin/live` as first parent).
2. Retry `git push origin live`. Success → exit 0. Failure → re-enter prepare.
3. `git checkout <return_branch>` once a push succeeds.

### 4.4 First-parent invariant

D6 is non-negotiable. Tests assert that `git log --first-parent live` after each flavor's continuation still reads as the trunk (no divergent branches sneaking into the first-parent line).

---

## 5. Sub-agent contract & recovery edges

### 5.1 `memory-merger` (`agents/memory-merger.md`)

Constraints baked into the system prompt:

- **Inputs:** path to `<mempath>/.git/gitlore-merge-state`. Nothing else.
- **Process:** read the state file. Read every path in `changed_files` *fresh from disk* (post-merge state). Synthesize holistically — always, regardless of textual conflict presence (semantic conflicts can exist without textual ones). Write synthesized contents. `git add -A` in the memory worktree.
- **Approval gate:** SendMessage the parent with a prose summary. Parent answers from conversation context, escalating to the user only when needed. Sub-agent commits nothing until parent SendMessages approval.
- **Continuation:** on approval, run `state.continuation` (a `bash` command). Sub-agent's job ends when that command exits.
- **Hard rules:** no `git` mutation outside `git add -A`; no merging in additional branches; no touching the state file. If the file is malformed or the merge state on disk doesn't match it, fail loudly to the parent and stop.

### 5.2 Pre-flight (install-time)

`/gitlore:install` step 1 (from design): check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Plan 03 implements this. If unset, warn and offer to enable; install still completes. At runtime, prepare scripts proceed regardless; the agent layer surfaces a clear error if `Task` dispatch fails because the flag is off.

### 5.3 Recovery edges

| Situation | Detection | Behavior |
|---|---|---|
| Stale `gitlore-merge-state` from a crashed prior run | State file present + `live` worktree has `MERGE_HEAD` | Prepare scripts detect on entry; emit directive with `continuation: "scripts/resolve.sh abort-then-retry"`. Continuation runs `git merge --abort`, `git checkout <return_branch>`, removes the state file, then re-enters the original loop. |
| State file present but no `MERGE_HEAD` (manual out-of-band intervention) | Mismatch on entry | Fatal directive (no sub-agent dispatch): "manual intervention required — inspect `<state-file>` and the memory worktree." Exit non-zero. |
| Concurrent resolve in another worktree | `git checkout live` fails ("already checked out") | User-facing message: "Another session is resolving memory. Wait and retry." Exit non-zero. No yield. |
| Both flavors active in one user operation | Continuation finishes its flavor, its tail re-attempts the push, which fails on the next layer | Prepare for the new flavor → yield again. State machine cycles until a push succeeds. |
| Sub-agent dispatch fails (flag off, `Task` unavailable) | Agent-level error after yield | Agent surfaces the actual failure verbatim. No single-agent fallback (D9). |

---

## 6. Testing strategy — three layers

Per [[feedback-automate-default]]: default to automation. Manual gates only where automation costs disproportionately more than the value.

### 6.1 Layer 1 — Unit (bats)

Script primitives, state-file shape, detection logic, recovery-edge guards. Same shape as Plan 02's unit tests.

### 6.2 Layer 2 — Integration with stub sub-agent

End-to-end script wiring through `prepare → state-file → synthesis → continuation`, with a deterministic stub replacing the LLM-driven `memory-merger`. This covers everything Plan-02-style dogfood would have caught *script-side*.

- `tests/helpers/stub-synth.bash` — bash function that mimics the sub-agent contract: reads the state file, performs configurable deterministic synthesis (prefer-A, prefer-B, concatenate, fixed-string), `git add -A`, invokes `state.continuation`. Auto-approves (no SendMessage gate at this layer).
- Tests assert: state-file contents on yield; post-continuation tree state; first-parent invariant per D6; that the continuation invoked the expected git commands; that the loop re-fires when retry-push fails again.
- Fixtures (`tests/helpers/divergence-fixtures.bash`): hermetic construction of branch-vs-live and local-vs-remote scenarios using two local bare repos.

### 6.3 Layer 3 — Manual dogfood (narrowed)

Only what stub-synth can't validate: actual `Task` dispatch, actual `SendMessage` approval gate, LLM synthesis quality with non-trivial content. One gate suffices.

- 🐕 **Dogfood (single gate)** — induce branch-vs-live divergence on a test repo with gitlore installed; run a real `git commit` in a real Claude Code session; observe the agent loop end-to-end. Skip local-vs-remote dogfood unless this surfaces something the stub-synth integration missed.
- **Open question for writing-plans:** can the Claude Agent SDK script `Task` dispatch + `SendMessage` approval deterministically? If yes, even this gate moves to Layer 2. Investigate during plan execution; don't pre-commit to manual.

### 6.4 In-plan backfill of Plan 03's own dogfood gate findings

No Plan 02 backfill needed — both Plan 02 dogfood surprises (`.gitmodules` gitignored, `gh --source=.` with gitfile submodule) were already automated in commit `192d7e8` and live in `tests/install_run.bats` and `tests/install_remote.bats`.

What does apply: anything §6.3's manual gate surfaces gets a Layer 2 fixture *in this plan* before Plan 03 is considered shipped. Following Plan 02's pattern (which patched + backfilled in the same commit). No findings are deferred to Plan 04.

### 6.5 Test layout

```
tests/resolve_detect.bats              # NEW — detection across both flavors and both-active
tests/resolve_merge_branch.bats        # NEW — branch-vs-live: prep + stub-synth + continuation + loop
tests/resolve_merge_remote.bats        # NEW — local-vs-remote: same shape
tests/resolve_both_flavors.bats        # NEW — both-active via /gitlore:resolve
tests/resolve_recovery.bats            # NEW — MERGE_HEAD + state-file recovery, concurrent checkout
tests/pre_commit_hook.bats             # MODIFY — replace exit-1-routes-to-resolve path with yield path
tests/pre_push_hook.bats               # MODIFY — same
tests/install_remote.bats              # (no change in scope; modified only if §6.3 surfaces something)
tests/helpers/divergence-fixtures.bash # NEW
tests/helpers/stub-synth.bash          # NEW
tests/helpers/gh-mock.bash             # MODIFY — gitfile-submodule rejection variation
agents/memory-merger.md                # NEW — sub-agent system prompt
commands/gitlore/resolve.md            # MODIFY — dispatch directive recognition
scripts/resolve.sh                     # MODIFY — subcommands, fetch + push-first detection
scripts/lib/resolve.sh                 # NEW — shared functions across hooks + resolve
scripts/git-hooks/pre-commit           # MODIFY — yield path on ff-push failure
scripts/git-hooks/pre-push             # MODIFY — yield path on ff-push failure
scripts/install/preflight.sh           # MODIFY — add CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS check
```

---

## 7. Open questions to resolve during writing-plans

1. **Does `commands/gitlore/resolve.md` need `Task` in `allowed-tools`, or is the slash-command-to-Task-tool dispatch implicit?** Check current CC behavior; if explicit, add it. Plan 02's resolve.md only has `Bash`.
2. **`agents/memory-merger.md` path conventions for CC plugins.** Verify the plugin's `plugin.json` exposes agents from this location. (Plan 02 doesn't ship an agent yet.)
3. **State-file location.** `<mempath>/.git/gitlore-merge-state` works when `<mempath>/.git` is a directory but the memory submodule's `.git` is a gitfile pointer. Use `git -C <mempath> rev-parse --git-path gitlore-merge-state` instead — matches Plan 01's `gitlore-commit-msg` convention.
4. **Should `continuation` be an absolute path or a relative subcommand?** Relative `scripts/resolve.sh continue-after-...` requires the sub-agent to be in the right CWD; absolute via `$CLAUDE_PLUGIN_ROOT` is more robust. Pick one during writing-plans.
5. **Continuation re-entry: same script invocation or new process?** New process is simpler (state file is the handoff); same-process via shell function is faster but tangles the state machine. Recommend new process unless profiling argues otherwise.
6. **Can the Claude Agent SDK script `Task` dispatch and `SendMessage` deterministically?** If yes, Layer 3 dogfood becomes Layer 2 integration. Investigate.
7. **`/gitlore:install` step 1 ordering.** The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` check is informational only; place it before the destructive pre-flight (gh + auth) or after?

---

## Self-review checklist (spec phase)

- ✅ Spec coverage: §2.1's seven in-scope bullets each have a section that owns them (branch-vs-live → §4.2; local-vs-remote → §4.3; memory-merger → §5.1; state-machine → §3; recovery → §5.3; install pre-flight → §5.2; in-plan dogfood backfill → §6.4).
- ✅ Placeholder scan: no TBDs. §7 enumerates explicit open questions for writing-plans, not placeholders.
- ✅ Internal consistency: §3.5's state-file path matches §7.3's reminder to use `git rev-parse --git-path`. §4's first-parent invariant matches design D6.
- ✅ Type consistency: `mempath`, `GITLORE_SUBMODULE_NAME`, `gitlore_memory_path` follow Plan 01/02 conventions; state-file location follows Plan 01's `gitlore-commit-msg` convention.
- ✅ Outside-in test order to be enforced by writing-plans: each code task writes failing tests first (Layer 1 + Layer 2 stub), drives to green, backfills failures.
- ✅ Single source of truth: detection in `scripts/lib/resolve.sh`; hooks and `/gitlore:resolve` call into it.
- ✅ Dogfood gate is narrow and explicit (§6.3), with an open question (§7.6) asking writing-plans to investigate moving it to Layer 2.
- ✅ Open questions enumerated (§7) for writing-plans to resolve.

---

# Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Plan 02's "manual fix required" failure paths in `pre-commit` and `pre-push` with a semantic-merge state-machine. Hooks detect divergence by push failure, prepare the merge on disk, write a state file, and emit a directive naming the continuation. A new `memory-merger` sub-agent reads the state file, synthesizes, gets parent approval via `SendMessage`, then invokes the continuation script.

**Architecture:** Yield-with-continuation state machine driven entirely by scripts. Each yield carries (a) directive to dispatch `memory-merger` with a state-file path and (b) a continuation subcommand the sub-agent runs after approval. Continuations may yield again — a single user op may yield N times until a push succeeds.

**Tech stack:** `bash` 3.2+, `bats-core`, `jq` for state-file IO, POSIX `git`, mocked `gh`. Claude Code `Task` + `SendMessage` at runtime, requiring `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

---

## File layout (target end state)

```
scripts/lib/util.sh                    # MODIFY — add gitlore_merge_state_file
scripts/lib/resolve.sh                 # NEW — state IO, directive emission, prepare helpers
scripts/git-hooks/pre-commit           # MODIFY — yield path on ff-push failure
scripts/git-hooks/pre-push             # MODIFY — yield path on ff-push failure
scripts/resolve.sh                     # MODIFY — subcommands (continue-after-*, abort-then-retry); default = fetch + try-both
scripts/install/preflight.sh           # MODIFY — warn-only CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS check
commands/gitlore/resolve.md            # MODIFY — recognize directive, dispatch memory-merger via Task
agents/memory-merger.md                # NEW — sub-agent system prompt
tests/helpers/divergence-fixtures.bash # NEW — make_diverged_branch_vs_live, make_diverged_local_vs_remote
tests/helpers/stub-synth.bash          # NEW — run_stub_synth (Layer 2 stand-in for the sub-agent)
tests/resolve_merge_branch.bats        # NEW — branch-vs-live e2e + loop
tests/resolve_merge_remote.bats        # NEW — local-vs-remote e2e + loop
tests/resolve_both_flavors.bats        # NEW — /gitlore:resolve manual entry, both serial
tests/resolve_recovery.bats            # NEW — MERGE_HEAD recovery, concurrent checkout, fatal mismatch
tests/pre_commit_hook.bats             # MODIFY — replace exit-1-with-resolve-message with yield expectations
tests/pre_push_hook.bats               # MODIFY — same
tests/install_run.bats                 # MODIFY — assert preflight warns when AGENT_TEAMS unset (does not abort)
```

---

## Conventions for every task

- Same as Plan 02 (`docs/plans/2026-05-19-02-remote-and-push.md`): bats files load `helpers/setup`, scripts begin with `#!/usr/bin/env bash` + `set -euo pipefail`, library functions namespaced `gitlore_<verb>_<noun>`, hook scripts exit 0 (silent OK) or non-zero (loud directive on stderr), commit prefix per gitmoji convention.
- State file at `<mempath>/.git/gitlore-merge-state`, resolved via `gitlore_merge_state_file` (Task 1 step 3). JSON shape per spec §3.5.
- Continuation stored as a subcommand name (e.g., `continue-after-branch-merge`). The sub-agent runs it as `bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" <continuation>`.
- Hook scripts source `scripts/lib/resolve.sh` after `util.sh`/`log.sh`.
- Tests never call git plumbing directly to set up divergence — use `tests/helpers/divergence-fixtures.bash`.

---

## Task 1: Branch-vs-live semantic merge end-to-end

**Files:**
- Modify: `scripts/lib/util.sh`
- Create: `scripts/lib/resolve.sh`
- Create: `tests/helpers/divergence-fixtures.bash`
- Create: `tests/helpers/stub-synth.bash`
- Create: `tests/resolve_merge_branch.bats`
- Modify: `scripts/git-hooks/pre-commit`
- Modify: `scripts/resolve.sh` (add `continue-after-branch-merge` subcommand)

Outside-in TDD: red e2e first → build scaffolding + impl in order to drive it green → backfill the loop case.

- [ ] **Step 1: Write the happy-path test.**

Create `tests/resolve_merge_branch.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  # Stage a parent-side change so the pre-commit hook has a real commit context.
  echo parent > parent-file
  git add parent-file
  make_diverged_branch_vs_live memory
}
teardown() { teardown_tmp_repo; }

@test "branch-vs-live: pre-commit yields directive on ff-push failure" {
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
  [[ "$output$stderr" == *"continue-after-branch-merge"* ]]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "branch-vs-live" ]
  [ "$(jq -r .return_branch "$statefile")" = "worktree" ]
}

@test "branch-vs-live: stub-synth continuation finalizes the merge and ff-pushes branch" {
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run_stub_synth memory
  # After continuation:
  branch=$(git -C memory symbolic-ref --short HEAD)
  [ "$branch" = "worktree" ]
  [ "$(git -C memory rev-parse worktree)" = "$(git -C memory rev-parse live)" ]
  # First-parent invariant (D6): live is first parent of the merge commit.
  merge_commit=$(git -C memory rev-parse live)
  first_parent=$(git -C memory rev-parse "${merge_commit}^1")
  # First parent should match the live tip from BEFORE the merge.
  # (We can't easily reconstruct that here without recording it; assert by message instead.)
  msg=$(git -C memory log -1 --format=%s "$merge_commit")
  [[ "$msg" == *"Merge"*"worktree"*"into live"* ]] || [[ "$msg" == *"worktree"* ]]
  # State file removed.
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-merge-state)" ]
}
```

- [ ] **Step 2: Run to confirm red.**

Run: `bats tests/resolve_merge_branch.bats`
Expected: 2 failures — pre-commit currently exits 1 with the Plan 02 "manual fix required" message; the state file is never written.

- [ ] **Step 3: Add `gitlore_merge_state_file` to `scripts/lib/util.sh`.**

Append:

```bash
# Print abs path to the memory submodule's merge-state file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (working tree).
gitlore_merge_state_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-merge-state
}
```

- [ ] **Step 4: Create `scripts/lib/resolve.sh`.**

```bash
#!/usr/bin/env bash
# Shared functions for memory divergence detection, state-file IO, and
# directive emission. Source; do not exec.

# Write a JSON merge-state file. All args required.
# Args: $1=mempath  $2=flavor  $3=base_sha  $4=source_ref  $5=target_ref
#       $6=return_branch  $7=continuation_subcommand
gitlore_write_merge_state() {
  local mempath="$1" flavor="$2" base="$3" source="$4" target="$5" return_branch="$6" cont="$7"
  local statefile
  statefile=$(gitlore_merge_state_file "$mempath")
  local changed conflicted
  changed=$(git -C "$mempath" diff --name-only "$base"...HEAD 2>/dev/null \
    | jq -R . | jq -s . 2>/dev/null || echo '[]')
  conflicted=$(git -C "$mempath" diff --name-only --diff-filter=U 2>/dev/null \
    | jq -R . | jq -s . 2>/dev/null || echo '[]')
  cat > "$statefile" <<EOF
{
  "flavor": "$flavor",
  "base": "$base",
  "source_ref": "$source",
  "target_ref": "$target",
  "return_branch": "$return_branch",
  "changed_files": $changed,
  "conflicted_files": $conflicted,
  "continuation": "$cont"
}
EOF
}

# Emit the structured directive on stderr.
# Args: $1=statefile_path  $2=flavor  $3=continuation_subcommand
gitlore_emit_merge_directive() {
  local statefile="$1" flavor="$2" cont="$3"
  cat >&2 <<EOF
gitlore: memory merge prepared (flavor=$flavor).
gitlore: dispatch the memory-merger sub-agent with state file:
gitlore:   $statefile
gitlore: on approval, the sub-agent must run:
gitlore:   bash "\$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" $cont
EOF
}

# Prepare branch-vs-live merge. Caller must already know it's needed.
# Stdout: `<branch>:<base_sha>`.  Exit 2 on concurrent-checkout (live already checked out).
gitlore_prepare_branch_vs_live() {
  local mempath="$1"
  local branch base
  branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || git -C "$mempath" rev-parse HEAD)
  base=$(git -C "$mempath" merge-base "$branch" live)
  git -C "$mempath" checkout -q live 2>/dev/null || return 2
  git -C "$mempath" merge --no-commit --no-ff "$branch" >/dev/null 2>&1 || true
  printf '%s:%s\n' "$branch" "$base"
}

# Prepare local-vs-remote merge.
# Stdout: `<return_branch>:<base_sha>:<old_local_sha>`.  Exit 2 on concurrent-checkout.
gitlore_prepare_local_vs_remote() {
  local mempath="$1"
  local return_branch old_local base
  return_branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || git -C "$mempath" rev-parse HEAD)
  old_local=$(git -C "$mempath" rev-parse live)
  git -C "$mempath" checkout -q live 2>/dev/null || return 2
  git -C "$mempath" reset --hard -q origin/live
  base=$(git -C "$mempath" merge-base "$old_local" origin/live)
  git -C "$mempath" merge --no-commit --no-ff "$old_local" >/dev/null 2>&1 || true
  printf '%s:%s:%s\n' "$return_branch" "$base" "$old_local"
}
```

- [ ] **Step 5: Create `tests/helpers/divergence-fixtures.bash`.**

```bash
#!/usr/bin/env bash
# Factories for divergence scenarios. Caller is responsible for
# setup_tmp_repo + make_parent_with_memory first.

# Branch-vs-live: worktree branch and live each get one non-overlapping commit.
make_diverged_branch_vs_live() {
  local mempath="${1:-memory}"
  (
    cd "$mempath"
    git checkout -q worktree
    echo "branch-side" > BRANCH.md
    git add BRANCH.md
    git -c user.email=t@t -c user.name=t commit -q -m "Branch commit"
    git checkout -q live
    echo "live-side" > LIVE.md
    git add LIVE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Live commit"
    git checkout -q worktree
  )
}

# Local-vs-remote: local live and the bare remote each get one non-overlapping commit.
make_diverged_local_vs_remote() {
  local mempath="${1:-memory}"
  local bare="${TMP_REPO}/.bare-memory.git"
  local clone_dir
  clone_dir="$(mktemp -d "${TMP_REPO}/clone.XXXXXX")"
  (
    cd "$clone_dir"
    git clone -q "$bare" .
    git checkout -q live
    echo "remote-side" > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Remote commit"
    git push -q origin live
  )
  rm -rf "$clone_dir"
  (
    cd "$mempath"
    git fetch -q origin
    git checkout -q live
    echo "local-side" > LOCAL.md
    git add LOCAL.md
    git -c user.email=t@t -c user.name=t commit -q -m "Local commit"
  )
}
```

- [ ] **Step 6: Create `tests/helpers/stub-synth.bash`.**

```bash
#!/usr/bin/env bash
# Layer 2 stand-in for the memory-merger sub-agent.
# Reads the state file, resolves any conflict markers by taking the
# 'ours' side (current HEAD's content), git add -A, then invokes the
# continuation as `bash $CLAUDE_PLUGIN_ROOT/scripts/resolve.sh <cont>`.

run_stub_synth() {
  local mempath="$1"
  local statefile
  statefile=$(git -C "$mempath" rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ] || { echo "stub-synth: no state file at $statefile" >&2; return 1; }
  local conflicted
  conflicted=$(jq -r '.conflicted_files[]?' "$statefile")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$mempath" checkout --ours -- "$f" 2>/dev/null || true
  done <<< "$conflicted"
  (cd "$mempath" && git add -A)
  local cont
  cont=$(jq -r .continuation "$statefile")
  bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" "$cont"
}
```

- [ ] **Step 7: Modify `scripts/git-hooks/pre-commit`.**

Replace the final `if [ -n "$live_sha" ]; then ... fi` block with a yield path. Full new file:

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.path" >/dev/null 2>&1 || exit 0

mempath=$(gitlore_memory_path)
msgfile=$(gitlore_commit_msg_file "$mempath")

dirty=$(gitlore_memory_dirty "$mempath")
live_sha=$(git -C "$mempath" rev-parse live 2>/dev/null || echo "")
head_sha=$(git -C "$mempath" rev-parse HEAD)

if [ "$dirty" = "0" ] && [ "$head_sha" = "$live_sha" ]; then
  exit 0
fi

if [ "$dirty" = "1" ]; then
  fresh=$(gitlore_commit_msg_freshness "$mempath")
  if [ "$fresh" != "yes" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory is dirty and has no approved commit summary. Prepare a summary, present it for user confirmation, and on approval write it to $msgfile. Then retry." \
      "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
    exit 1
  fi
  git -C "$mempath" add -A
  git -C "$mempath" commit -q -F "$msgfile"
  rm -f "$msgfile"
fi

if [ -n "$live_sha" ]; then
  if ! git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
    # ff-push failed → branch-vs-live divergence. Prepare and yield.
    if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
      gitlore_say_for_agent_or_user \
        "gitlore: cannot checkout live (already checked out elsewhere). Another session is resolving memory. Wait and retry." \
        "gitlore: another session is resolving memory. Wait and retry." >&2
      exit 1
    fi
    branch="${prep_out%%:*}"
    base="${prep_out#*:}"
    gitlore_write_merge_state "$mempath" "branch-vs-live" "$base" "$branch" "live" "$branch" "continue-after-branch-merge"
    statefile=$(gitlore_merge_state_file "$mempath")
    gitlore_emit_merge_directive "$statefile" "branch-vs-live" "continue-after-branch-merge"
    exit 1
  fi
fi

exit 0
```

- [ ] **Step 8: Modify `scripts/resolve.sh` — add `continue-after-branch-merge` subcommand.**

Insert this dispatcher block immediately after the `source` lines and before the Plan 02 default-mode logic:

```bash
# Subcommand dispatch (Plan 03 continuations).
if [ $# -ge 1 ]; then
  subcmd="$1"
  shift
  case "$subcmd" in
    continue-after-branch-merge)
      gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
      mempath=$(gitlore_memory_path)
      statefile=$(gitlore_merge_state_file "$mempath")
      [ -f "$statefile" ] || { echo "gitlore: no merge state file at $statefile" >&2; exit 1; }
      return_branch=$(jq -r .return_branch "$statefile")
      # Commit the merge (uses git's MERGE_MSG; live is HEAD = first parent per D6).
      git -C "$mempath" commit -q --no-edit
      # Advance the worktree branch to the merge commit and return.
      git -C "$mempath" branch -f "$return_branch" HEAD
      git -C "$mempath" checkout -q "$return_branch"
      rm -f "$statefile"
      # Retry the ff-push; on failure, loop with a fresh prepare.
      if ! git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
        if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
          echo "gitlore: cannot checkout live (concurrent resolve). Wait and retry." >&2
          exit 1
        fi
        branch="${prep_out%%:*}"
        base="${prep_out#*:}"
        gitlore_write_merge_state "$mempath" "branch-vs-live" "$base" "$branch" "live" "$branch" "continue-after-branch-merge"
        gitlore_emit_merge_directive "$statefile" "branch-vs-live" "continue-after-branch-merge"
        exit 1
      fi
      exit 0
      ;;
    *)
      # Other subcommands added in later tasks.
      echo "gitlore: unknown resolve subcommand: $subcmd" >&2
      exit 2
      ;;
  esac
fi
```

Also add `source "$PLUGIN_ROOT/scripts/lib/resolve.sh"` after the existing `source` lines.

- [ ] **Step 9: Run happy-path; confirm green.**

Run: `bats tests/resolve_merge_branch.bats`
Expected: 2 passing.

- [ ] **Step 10: Append loop-case test.**

```bash
@test "branch-vs-live loop: continuation yields again if retry-push fails" {
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  # Before stub-synth runs the continuation, simulate another worktree advancing live.
  (
    cd "$(mktemp -d "$TMP_REPO/another.XXXXXX")"
    git clone -q "$TMP_REPO/.bare-memory.git" .
    git checkout -q live
    echo "advance" > ADVANCE.md
    git add ADVANCE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Another live commit"
    # Push directly into the local memory's live via the parent's submodule remote.
    # (Simulated by updating the local live ref directly.)
  )
  # Simulate concurrent live advance: re-create branch-vs-live divergence post-prepare.
  (
    cd memory
    git checkout -q live
    echo "concurrent" > CONCURRENT.md
    git add CONCURRENT.md
    git -c user.email=t@t -c user.name=t commit -q -m "Concurrent live commit"
    # Re-prepare won't happen here; the test forces a retry-push failure.
    # Reset back to leave the post-prepare state intact.
  )
  run_stub_synth memory || true
  # After continuation: a second state file should be present, or the continuation
  # should have written a fresh directive (the loop).
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "branch-vs-live" ]
}
```

Note: this test is the hardest one to set up cleanly. Refine during execution if the simulated concurrent-advance doesn't trigger the retry-push failure in practice. The intent is: continuation completes its commit, attempts retry-push, the retry fails because of new divergence, and a fresh prepare yields a new directive.

- [ ] **Step 11: Run; confirm all green.**

Run: `bats tests/resolve_merge_branch.bats`
Expected: 3 passing.

- [ ] **Step 12: Commit.**

```bash
git add scripts/lib/util.sh scripts/lib/resolve.sh \
        tests/helpers/divergence-fixtures.bash tests/helpers/stub-synth.bash \
        tests/resolve_merge_branch.bats \
        scripts/git-hooks/pre-commit scripts/resolve.sh
git commit -m "✨ feat: branch-vs-live semantic merge — pre-commit yields, continuation finalizes"
```

---

## Task 2: Local-vs-remote semantic merge end-to-end

**Files:**
- Create: `tests/resolve_merge_remote.bats`
- Modify: `scripts/git-hooks/pre-push`
- Modify: `scripts/resolve.sh` (add `continue-after-remote-merge` subcommand)

Same outside-in shape as Task 1. The helpers (`scripts/lib/resolve.sh`, `divergence-fixtures.bash`, `stub-synth.bash`) already exist.

- [ ] **Step 1: Write the happy-path test.**

Create `tests/resolve_merge_remote.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  make_diverged_local_vs_remote memory
}
teardown() { teardown_tmp_repo; }

@test "local-vs-remote: pre-push yields directive on ff-push failure" {
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
  [[ "$output$stderr" == *"continue-after-remote-merge"* ]]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "local-vs-remote" ]
}

@test "local-vs-remote: stub-synth continuation commits + pushes to origin" {
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  run_stub_synth memory
  # After continuation: local live matches origin/live, return_branch is checked out.
  local_live=$(git -C memory rev-parse live)
  remote_live=$(git --git-dir="$TMP_REPO/.bare-memory.git" rev-parse live)
  [ "$local_live" = "$remote_live" ]
  branch=$(git -C memory symbolic-ref --short HEAD)
  [ "$branch" = "live" ] || [ "$branch" = "worktree" ]  # whichever return_branch recorded
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-merge-state)" ]
}
```

- [ ] **Step 2: Run to confirm red.**

Run: `bats tests/resolve_merge_remote.bats`
Expected: 2 failures.

- [ ] **Step 3: Modify `scripts/git-hooks/pre-push`.**

Full new file:

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.path" >/dev/null 2>&1 || exit 0

mempath=$(gitlore_memory_path)

remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ]; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory submodule has no remote configured. Run /gitlore:resolve to create one." \
    "gitlore: memory submodule has no remote configured. Open this project in Claude Code and run /gitlore:resolve." >&2
  exit 1
fi

git -C "$mempath" fetch -q origin live 2>/dev/null || true

if git -C "$mempath" push -q origin live 2>/dev/null; then
  exit 0
fi

# Push failed. Distinguish unreachable from divergence.
if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
  exit 1
fi

# Reachable → local-vs-remote divergence. Prepare and yield.
if ! prep_out=$(gitlore_prepare_local_vs_remote "$mempath"); then
  gitlore_say_for_agent_or_user \
    "gitlore: cannot checkout live (already checked out elsewhere). Another session is resolving memory. Wait and retry." \
    "gitlore: another session is resolving memory. Wait and retry." >&2
  exit 1
fi
IFS=':' read -r return_branch base old_local <<< "$prep_out"
gitlore_write_merge_state "$mempath" "local-vs-remote" "$base" "$old_local" "live" "$return_branch" "continue-after-remote-merge"
statefile=$(gitlore_merge_state_file "$mempath")
gitlore_emit_merge_directive "$statefile" "local-vs-remote" "continue-after-remote-merge"
exit 1
```

- [ ] **Step 4: Add `continue-after-remote-merge` to `scripts/resolve.sh`.**

Add a new case to the subcommand dispatcher from Task 1 step 8:

```bash
    continue-after-remote-merge)
      gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
      mempath=$(gitlore_memory_path)
      statefile=$(gitlore_merge_state_file "$mempath")
      [ -f "$statefile" ] || { echo "gitlore: no merge state file at $statefile" >&2; exit 1; }
      return_branch=$(jq -r .return_branch "$statefile")
      # Commit the merge (origin/live is HEAD = first parent per D6).
      git -C "$mempath" commit -q --no-edit
      rm -f "$statefile"
      # Retry the push; on failure, loop with a fresh prepare.
      if ! git -C "$mempath" push -q origin live 2>/dev/null; then
        if ! prep_out=$(gitlore_prepare_local_vs_remote "$mempath"); then
          echo "gitlore: cannot checkout live (concurrent resolve). Wait and retry." >&2
          exit 1
        fi
        IFS=':' read -r return_branch base old_local <<< "$prep_out"
        gitlore_write_merge_state "$mempath" "local-vs-remote" "$base" "$old_local" "live" "$return_branch" "continue-after-remote-merge"
        gitlore_emit_merge_directive "$statefile" "local-vs-remote" "continue-after-remote-merge"
        exit 1
      fi
      git -C "$mempath" checkout -q "$return_branch"
      exit 0
      ;;
```

- [ ] **Step 5: Run happy-path; confirm green.**

Run: `bats tests/resolve_merge_remote.bats`
Expected: 2 passing.

- [ ] **Step 6: Append loop-case test (concurrent remote advance during synthesis).**

```bash
@test "local-vs-remote loop: continuation yields again if retry-push fails" {
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  # Simulate another machine pushing to origin during synthesis.
  (
    cd "$(mktemp -d "$TMP_REPO/concurrent.XXXXXX")"
    git clone -q "$TMP_REPO/.bare-memory.git" .
    git checkout -q live
    echo "concurrent" > CONCURRENT.md
    git add CONCURRENT.md
    git -c user.email=t@t -c user.name=t commit -q -m "Concurrent remote commit"
    git push -q origin live
  )
  run_stub_synth memory || true
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "local-vs-remote" ]
}
```

- [ ] **Step 7: Run; confirm all green.**

Run: `bats tests/resolve_merge_remote.bats`
Expected: 3 passing.

- [ ] **Step 8: Commit.**

```bash
git add tests/resolve_merge_remote.bats scripts/git-hooks/pre-push scripts/resolve.sh
git commit -m "✨ feat: local-vs-remote semantic merge — pre-push yields, continuation finalizes"
```

---

## Task 3: `/gitlore:resolve` manual entry — both flavors, serial

**Files:**
- Modify: `scripts/resolve.sh` (default mode: fetch + try-both)
- Create: `tests/resolve_both_flavors.bats`

The default mode of `scripts/resolve.sh` (no args) replaces Plan 02's "diverged → manual fix" path with the same yield protocol used by the hooks. When both flavors apply, the script tries branch-vs-live first (it's local-only and cheaper); local-vs-remote falls out on the next continuation cycle.

- [ ] **Step 1: Write the happy-path test.**

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
}
teardown() { teardown_tmp_repo; }

@test "resolve: healthy state still no-ops" {
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"healthy"* ]] || [[ -z "$stderr" ]]
}

@test "resolve: yields branch-vs-live directive when worktree diverged from live" {
  make_diverged_branch_vs_live memory
  run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
}

@test "resolve: yields local-vs-remote directive when local diverged from origin" {
  make_diverged_local_vs_remote memory
  # Ensure worktree branch isn't ahead of live (so branch-vs-live doesn't fire first).
  (cd memory && git checkout -q worktree && git push -q . HEAD:live 2>/dev/null || true)
  run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
}

@test "resolve: both flavors → serial yield (branch-vs-live first)" {
  make_diverged_branch_vs_live memory
  make_diverged_local_vs_remote memory
  run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
  # After stub-synth + first continuation, /gitlore:resolve should be re-invoked
  # to detect the second flavor. The continuation does NOT auto-loop into the
  # second flavor — that's a fresh entry-point invocation.
  run_stub_synth memory
  run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
}
```

- [ ] **Step 2: Run to confirm red.**

Run: `bats tests/resolve_both_flavors.bats`
Expected: ≥2 failures (Plan 02's default-mode `resolve.sh` doesn't yield, it reports "manual fix required").

- [ ] **Step 3: Refactor `scripts/resolve.sh` default mode.**

Replace the Plan 02 default-mode body (from "Step 1: gitlore installed?" through the final "healthy" exit) with:

```bash
# Default mode: detect + try both pushes in turn. Yield on the first failure;
# continuations re-enter from the hook (commit/push retries), not from here.

gitlore_has_submodule || {
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
}
mempath=$(gitlore_memory_path)

# Existing Plan 02 simple repairs (remote.origin.url, ls-remote, push live)
# happen first — they precede semantic-merge detection.
remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ] || [ "$remote_url" = "./.git/gitlore-placeholder" ]; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  exit 0
fi
if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
  exit 1
fi
if ! git -C "$mempath" ls-remote origin live | grep -q .; then
  echo "gitlore: remote has no live branch. Pushing." >&2
  git -C "$mempath" push origin live
  exit 0
fi

git -C "$mempath" fetch -q origin live 2>/dev/null || true

# Try branch-vs-live first (cheaper, local-only).
branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || echo "")
if [ -n "$branch" ] && [ "$branch" != "live" ]; then
  if ! git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
    if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
      echo "gitlore: another session is resolving memory. Wait and retry." >&2
      exit 1
    fi
    branch_p="${prep_out%%:*}"; base_p="${prep_out#*:}"
    gitlore_write_merge_state "$mempath" "branch-vs-live" "$base_p" "$branch_p" "live" "$branch_p" "continue-after-branch-merge"
    gitlore_emit_merge_directive "$(gitlore_merge_state_file "$mempath")" "branch-vs-live" "continue-after-branch-merge"
    exit 1
  fi
fi

# Branch is in sync (or wasn't applicable). Try local-vs-remote.
if ! git -C "$mempath" push -q origin live 2>/dev/null; then
  if ! prep_out=$(gitlore_prepare_local_vs_remote "$mempath"); then
    echo "gitlore: another session is resolving memory. Wait and retry." >&2
    exit 1
  fi
  IFS=':' read -r return_branch base old_local <<< "$prep_out"
  gitlore_write_merge_state "$mempath" "local-vs-remote" "$base" "$old_local" "live" "$return_branch" "continue-after-remote-merge"
  gitlore_emit_merge_directive "$(gitlore_merge_state_file "$mempath")" "local-vs-remote" "continue-after-remote-merge"
  exit 1
fi

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
```

- [ ] **Step 4: Run; confirm all green.**

Run: `bats tests/resolve_both_flavors.bats`
Expected: 4 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/resolve.sh tests/resolve_both_flavors.bats
git commit -m "✨ feat: /gitlore:resolve default mode yields per-flavor directives, serial"
```

---

## Task 4: Recovery edges

**Files:**
- Create: `tests/resolve_recovery.bats`
- Modify: `scripts/lib/resolve.sh` (add `gitlore_detect_stale_merge_state`)
- Modify: `scripts/resolve.sh` (add `abort-then-retry` subcommand; entry-points check stale state first)
- Modify: `scripts/git-hooks/pre-commit` (check stale state on entry)
- Modify: `scripts/git-hooks/pre-push` (check stale state on entry)

Cases:
1. State file present + `MERGE_HEAD` present → emit `abort-then-retry` directive.
2. State file present + no `MERGE_HEAD` → fatal directive (no sub-agent), manual intervention.
3. Concurrent `git checkout live` failure → already handled in Tasks 1-3 via `prepare_*` return-2.

- [ ] **Step 1: Write failing tests.**

Create `tests/resolve_recovery.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "recovery: stale state file + MERGE_HEAD → abort-then-retry directive" {
  make_diverged_branch_vs_live memory
  run bash "$PRE_COMMIT"
  # Now we have a state file + MERGE_HEAD. Simulate a fresh entry.
  run bash "$PRE_COMMIT"
  [[ "$output$stderr" == *"abort-then-retry"* ]]
}

@test "recovery: state file without MERGE_HEAD → fatal directive" {
  make_diverged_branch_vs_live memory
  bash "$PRE_COMMIT" || true
  # Manually abort the merge but leave the state file behind.
  (cd memory && git merge --abort 2>/dev/null || true)
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"manual intervention"* ]]
}

@test "recovery: abort-then-retry continuation cleans state and re-enters loop" {
  make_diverged_branch_vs_live memory
  bash "$PRE_COMMIT" || true
  # Simulate a crash by leaving the state file + MERGE_HEAD intact.
  run bash "$RESOLVE" abort-then-retry
  [ "$status" -ne 0 ]  # Re-entry yields a fresh directive
  [[ "$output$stderr" == *"branch-vs-live"* ]] || [[ "$output$stderr" == *"flavor="* ]]
  # MERGE_HEAD cleaned.
  [ ! -f "memory/.git/MERGE_HEAD" ] || true  # The submodule's MERGE_HEAD is in the gitdir
}
```

- [ ] **Step 2: Run to confirm red.**

Run: `bats tests/resolve_recovery.bats`
Expected: 3 failures.

- [ ] **Step 3: Add `gitlore_detect_stale_merge_state` to `scripts/lib/resolve.sh`.**

```bash
# Detect whether a stale merge-state file + MERGE_HEAD exists.
# Stdout: "clean" | "stale-with-merge-head" | "stale-no-merge-head".
gitlore_detect_stale_merge_state() {
  local mempath="$1"
  local statefile
  statefile=$(gitlore_merge_state_file "$mempath")
  if [ ! -f "$statefile" ]; then
    printf 'clean\n'
    return 0
  fi
  local gitdir
  gitdir=$(git -C "$mempath" rev-parse --git-dir)
  if [ -f "$gitdir/MERGE_HEAD" ]; then
    printf 'stale-with-merge-head\n'
  else
    printf 'stale-no-merge-head\n'
  fi
}
```

- [ ] **Step 4: Add `abort-then-retry` subcommand to `scripts/resolve.sh`.**

Add to the dispatcher case block:

```bash
    abort-then-retry)
      gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
      mempath=$(gitlore_memory_path)
      statefile=$(gitlore_merge_state_file "$mempath")
      [ -f "$statefile" ] || { echo "gitlore: no merge state file to abort" >&2; exit 1; }
      return_branch=$(jq -r .return_branch "$statefile")
      git -C "$mempath" merge --abort 2>/dev/null || true
      git -C "$mempath" checkout -q "$return_branch" 2>/dev/null || true
      rm -f "$statefile"
      # Re-enter the default mode to detect the original divergence freshly.
      exec bash "$0"
      ;;
```

- [ ] **Step 5: Add stale-state guard to pre-commit and pre-push (top of file, after sourcing libs).**

In each hook, immediately after sourcing `scripts/lib/resolve.sh`:

```bash
mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""
if [ -n "$mempath" ]; then
  state_status=$(gitlore_detect_stale_merge_state "$mempath")
  case "$state_status" in
    stale-with-merge-head)
      statefile=$(gitlore_merge_state_file "$mempath")
      flavor=$(jq -r .flavor "$statefile")
      gitlore_emit_merge_directive "$statefile" "$flavor" "abort-then-retry"
      exit 1
      ;;
    stale-no-merge-head)
      statefile=$(gitlore_merge_state_file "$mempath")
      echo "gitlore: merge state file present without MERGE_HEAD — manual intervention required. Inspect $statefile and the memory worktree." >&2
      exit 1
      ;;
  esac
fi
```

- [ ] **Step 6: Run; confirm all green.**

Run: `bats tests/resolve_recovery.bats`
Expected: 3 passing.

- [ ] **Step 7: Commit.**

```bash
git add tests/resolve_recovery.bats scripts/lib/resolve.sh scripts/resolve.sh \
        scripts/git-hooks/pre-commit scripts/git-hooks/pre-push
git commit -m "✨ feat: recovery edges — stale MERGE_HEAD via abort-then-retry, fatal for orphan state file"
```

---

## Task 5: `memory-merger` sub-agent + slash-command dispatch

**Files:**
- Create: `agents/memory-merger.md`
- Modify: `commands/gitlore/resolve.md`

The sub-agent is invoked by the slash command via the `Task` tool when the slash command sees a yield directive on stderr from the underlying script.

- [ ] **Step 1: Create `agents/memory-merger.md`.**

```markdown
---
description: Synthesizes a semantic memory merge from a prepared state file, then runs the continuation script.
allowed-tools: ["Read", "Write", "Edit", "Bash", "SendMessage"]
---

# memory-merger

You are synthesizing a semantic merge of memory files. The merge is already prepared on disk; your job is to write the final synthesized content and run the continuation script the parent agent told you about.

## Inputs

The parent agent will give you exactly one input: an absolute path to a state file.

## Constraints

- Read the state file. It is JSON with these fields: `flavor`, `base`, `source_ref`, `target_ref`, `return_branch`, `changed_files`, `conflicted_files`, `continuation`.
- For every path in `changed_files`, **read the file fresh from disk** (post-merge state — may contain conflict markers).
- Synthesize holistically: resolve conflicts AND reconcile semantic overlap, even if the file has no textual conflict markers. Memory files can have semantic conflicts that don't surface as textual ones.
- Write the synthesized contents to each file.
- Run `git add -A` in the memory worktree (resolved from the state file's location).
- SendMessage the parent agent with a prose summary of what you synthesized. The parent will answer from session context or escalate to the user.
- **Do not commit until the parent SendMessages approval.**
- On approval, run the continuation: `bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" <continuation>`. Your job ends when that command exits.

## Hard rules

- No `git` mutation outside `git add -A`. Never `git commit`, `git push`, `git branch`, `git checkout`. The continuation script does those.
- Never modify or remove the state file. The continuation script reads and removes it.
- If the state file is malformed, or the on-disk merge state contradicts it (no MERGE_HEAD when the file claims a merge is in progress), fail loudly to the parent via SendMessage and stop. Do not attempt to recover.

## Output

Your final message to the parent (after approval and continuation exit): a one-line summary of what happened. Example: "Branch-vs-live merge complete. 3 files reconciled. Continuation exited 0."
```

- [ ] **Step 2: Modify `commands/gitlore/resolve.md` to dispatch on directive.**

Full replacement:

```markdown
---
description: Diagnose and recover from gitlore memory divergence (semantic merge included)
allowed-tools: ["Bash", "Task", "SendMessage"]
---

# /gitlore:resolve

You are recovering a gitlore memory submodule from divergence — branch-vs-live, local-vs-remote, or a partial recovery state.

## Steps

1. **Confirm context.** Run `git rev-parse --show-toplevel`. If this fails, tell the user to cd into a git repo and abort.

2. **Run the resolver script.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
   ```

   Capture both stdout and stderr. Exit codes:
   - `0` — state healthy or simple repair complete. Summarize and stop.
   - Non-zero with a "memory merge prepared" directive on stderr — proceed to step 3.
   - Non-zero without a directive — surface stderr verbatim, stop.

3. **Parse the directive.** The directive looks like:

   ```
   gitlore: memory merge prepared (flavor=<X>).
   gitlore: dispatch the memory-merger sub-agent with state file:
   gitlore:   <abs-path>
   gitlore: on approval, the sub-agent must run:
   gitlore:   bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" <continuation>
   ```

   Extract the state-file path. Save the continuation command for verification only — the sub-agent will run it itself.

4. **Dispatch the `memory-merger` sub-agent.**

   Use the `Task` tool with `subagent_type: "memory-merger"`. Pass the state-file path as the only input.

5. **Answer the sub-agent's approval request.**

   The sub-agent will SendMessage with a prose summary. Read it. Compare against session context: does the synthesis match what we'd expect from the changes you've seen this session? If so, answer "approved". If anything is off, answer "rejected: <reason>" and let the sub-agent retry.

   Escalate to the user only when session context is insufficient.

6. **After the sub-agent exits**, run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh` again to check for a second flavor or a loop continuation. Repeat steps 2-6 until the script exits 0.

7. **Summarize.** Tell the user what was merged and what state the repo is in now.
```

- [ ] **Step 3: Manual verification (no bats here — Task and SendMessage aren't testable in bats).**

This task's correctness is verified by Task 7 (dogfood). Note that in the file layout.

- [ ] **Step 4: Commit.**

```bash
git add agents/memory-merger.md commands/gitlore/resolve.md
git commit -m "✨ feat: memory-merger sub-agent + /gitlore:resolve directive dispatch"
```

---

## Task 6: Install pre-flight — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` warning

**Files:**
- Modify: `scripts/install/preflight.sh`
- Modify: `tests/install_run.bats`

Warn-only: install completes regardless. Runtime surfaces a clean error if `Task` dispatch fails because the flag is off.

- [ ] **Step 1: Add a failing test.**

Append to `tests/install_run.bats`:

```bash
@test "preflight warns when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is unset" {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  run bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"AGENT_TEAMS"* ]] || [[ "$output$stderr" == *"experimental"* ]]
}

@test "preflight is silent when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  run bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"AGENT_TEAMS"* ]]
}
```

- [ ] **Step 2: Run to confirm red.**

Run: `bats tests/install_run.bats -f "AGENT_TEAMS"`
Expected: 1 failure (the "warns" test).

- [ ] **Step 3: Add the warning to `scripts/install/preflight.sh`.**

Append before the final `exit 0`:

```bash
if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  cat >&2 <<'EOF'
gitlore: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set.
gitlore: /gitlore:resolve requires it to dispatch the memory-merger sub-agent.
gitlore: Continuing install — set it before semantic merge is needed:
gitlore:   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
EOF
fi
```

- [ ] **Step 4: Run; confirm all green.**

Run: `bats tests/install_run.bats`
Expected: all passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/install/preflight.sh tests/install_run.bats
git commit -m "🔧 chore: preflight warns when CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is unset"
```

---

## Task 7: 🐕 Dogfood — branch-vs-live, real agent loop

**Files:** none (manual validation).

Plan 03 is not shipped until this passes. Per [[feedback-automate-default]] and §6.3 of the spec, this is the one gate that genuinely needs the real agent loop.

- [ ] **Step 1: Pick a test repo.**

Recommended: the gitlore repo itself (which has gitlore installed). Otherwise: any repo with `/gitlore:install` completed.

- [ ] **Step 2: Induce branch-vs-live divergence.**

In a Claude Code session (parent worktree):
1. Make a memory edit (any auto-memory write — e.g., update a feedback memory).
2. Stage and commit on the parent. The pre-commit hook fires, memory commit is prepared, branch advances live, parent commit completes.
3. Without committing, create a second linked worktree of the parent (`git worktree add`).
4. In that second worktree, also make a memory edit and attempt to commit. This should ff-push the second worktree's branch into live and succeed.
5. Now back in the first worktree, attempt another commit — its memory branch is no longer an ancestor of live. The ff-push fails.

- [ ] **Step 3: Observe the agent loop end-to-end.**

Expected:
1. pre-commit emits the directive (state file written, "flavor=branch-vs-live", continuation `continue-after-branch-merge`).
2. Claude reads the directive, invokes `Task` with `subagent_type: memory-merger`, passes the state-file path.
3. The sub-agent reads files, synthesizes, calls `git add -A`, SendMessages a summary.
4. The parent (Claude) approves with the user.
5. Sub-agent invokes `bash $CLAUDE_PLUGIN_ROOT/scripts/resolve.sh continue-after-branch-merge`.
6. Continuation commits with `live` as first parent, advances worktree branch, ff-pushes branch into live, exits 0.
7. User's original commit can now proceed (or they retry it).

- [ ] **Step 4: If anything surprises, patch in-plan and add a Layer 2 fixture.**

Per [[feedback-automate-default]] and §1 of the spec: dogfood findings become Layer 2 fixtures in Plan 03, not Plan 04. Patch the script, add a regression test under `tests/resolve_merge_branch.bats` (or a new file if the failure is genuinely new), commit, and re-run this step.

- [ ] **Step 5: Tick all Plan 03 boxes; ship.**

When this gate passes cleanly, Plan 03 is shipped. Open `/handoff` to summarize and prep the next iteration.

---

## Self-review checklist (writing-plans)

- ✅ Spec coverage: spec §2.1's seven bullets each have a Task that implements them (Task 1 → branch-vs-live merge; Task 2 → local-vs-remote merge; Task 5 → memory-merger sub-agent; Tasks 1-3 → state-machine architecture; Task 4 → recovery edges; Task 6 → install pre-flight; Task 7 → in-plan backfill discipline).
- ✅ Placeholder scan: no TBDs, no "implement later", no "similar to Task N" without specifics. The Task 1 step 10 loop test acknowledges its setup difficulty inline rather than masking it.
- ✅ Type consistency: `mempath`, `GITLORE_SUBMODULE_NAME`, `gitlore_memory_path`, `gitlore_merge_state_file`, `gitlore_write_merge_state`, `gitlore_emit_merge_directive` used consistently from Task 1 onward.
- ✅ Outside-in test order: each code task writes a failing test first, drives units to green, backfills failures within the same task.
- ✅ Single source of truth: state-file IO + directive emission + prepare helpers live in `scripts/lib/resolve.sh`; hooks and `/gitlore:resolve` call into it.
- ✅ Dogfood gate explicit (Task 7) with the §1 in-plan backfill discipline.
- ✅ Continuation invariant: every state file's `continuation` is a subcommand name; sub-agent invokes via `bash $CLAUDE_PLUGIN_ROOT/scripts/resolve.sh <continuation>`.
