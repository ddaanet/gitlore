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
