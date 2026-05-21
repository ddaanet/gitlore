# gitlore Plan 02 — Remote Creation and Pre-Push

> **Status:** spec / design. Implementation plan (task-by-task breakdown) will be expanded from this document by `superpowers:writing-plans`.

**Goal:** After `/gitlore:install` completes on a fresh repo, the user can `git commit` and `git push` and their memory submodule's `live` branch propagates to a remote, all in one command. No second step.

**Reference:** `docs/design.md` is the authoritative spec. Where this plan disagrees with the design, the design wins; flag the divergence in a PR comment before deviating. Plan 01 (`docs/plans/2026-05-15-01-local-memory-pipeline.md`) is the predecessor; this plan builds on its installed state.

---

## 1. Lessons-learned opener (Plan 01 retrospective)

Plan 01 shipped with 64 passing tests and was caught short by three classes of issue when dogfooded on the gitlore repo itself. Plan 02 should not repeat them.

### 1.1 Path-mangling assumption (commit `d47784d`)

Claude Code stores per-project files under `~/.claude/projects/<encoded-path>/`, where the encoding rule replaces `/` with `-` *but also* mangles non-alphanumeric characters in path components. Plan 01's auto-memory migration used a synthetic encoding that matched its own fixture, not real Claude Code behavior. The fixture passed; the real install failed silently.

**Lesson for Plan 02:** any path the agent's runtime hands us at install time must be validated against what `claude` itself produces, not what our fixtures assume.

### 1.2 PostToolUse silent failure (commit `041eebf`)

The PostToolUse hook assumed `.claude/settings.json` existed. On repos where it didn't, the hook errored out before its no-op guard could fire, and the error was suppressed by Claude Code's hook plumbing. The hook had a guard for the *content* of settings.json but not for the file's existence.

**Lesson for Plan 02:** every hook script must guard its preconditions in the order they could fail. File-existence guards precede content-existence guards. No script may rely on Claude Code surfacing its errors — write failures must be observable to a human running it directly.

### 1.3 Install staging contract (commit `5fef491`)

Plan 01's install path wrote `.claude/settings.json`, `.gitignore`, and `.claude/gitlore-hook-setup` to disk but never staged them. The fixture suite asserted file existence, not staging state. On the real repo, the user saw an install that promised "review the staged changes" then handed them an empty `git diff --staged`. The same commit also exposed that `git add memory` silently fails to register a submodule as a gitlink in modern git — the install needed `git update-index --add --cacheinfo 160000,<sha>,memory` instead.

**Lesson for Plan 02:** when install promises "we staged X," tests must assert X is in `git diff --cached`, not just on disk. And gitlink operations need explicit cacheinfo, not naive `git add`.

### 1.4 Process lesson: dogfood early

These three issues all surfaced within minutes of dogfooding Plan 01 on the gitlore repo itself. They could not have been surfaced by the fixture suite, because the fixtures encoded what was expected to vary. Plan 02 bakes dogfooding *into* its task order — see Section 5.

---

## 2. Scope

### 2.1 In scope

- **Phase A — pre-push hook.** Before any outer push to the parent repo's remote, the memory submodule's `live` branch ff-pushes to its own remote. If the memory push fails, the outer push aborts.
- **Phase B — remote creation flow.** `/gitlore:install` proactively creates a GitHub repo for the memory submodule, sets it as `origin`, and pushes the initial `live` branch — all during install, gated by a pre-flight check.
- **`/gitlore:resolve` — recovery command.** A new CC slash command that diagnoses partial / broken remote state and routes to specific repair actions. In Plan 02, it handles the failure modes that Phase A and Phase B can produce.
- **Shared remote-creation code path.** The logic Phase B uses to create a remote must be callable from `/gitlore:resolve` too — single source of truth.

### 2.2 Out of scope (deferred to later plans)

- Auto-resolving non-fast-forward divergence between local `live` and remote `live`.
- Interactive force-push prompts.
- Multi-repo / multi-remote topologies.
- GitHub Enterprise endpoints, non-GitHub remotes (GitLab, Bitbucket), or non-`gh` toolchains.
- `WorktreeCreate` / `WorktreeRemove` hooks (Plan 04).
- Clone-from-remote smoke test, polish, expanded docs (Plan 05).

---

## 3. Phase A — Pre-push hook

### 3.1 Contract

When the user runs `git push` (or any operation that fires the pre-push git hook) in a parent repo with gitlore installed:

1. The user's hook manager (or direct-wired `.git/hooks/pre-push`) invokes `.git/gitlore-pre-push` alongside the user's own pre-push commands. The user's commands run via their hook manager's normal ordering — gitlore does not wrap or execute them.
2. The `.git/gitlore-pre-push` wrapper invokes `$(git config gitlore.hooksDir)/pre-push`.
3. That script pushes the memory submodule's `live` branch to its `origin` (ff-only).
4. If memory push succeeds, the wrapper exits 0 and the outer push proceeds.
5. If memory push fails, the wrapper exits non-zero with an actionable message routed (where applicable) to `/gitlore:resolve`.

> **Architectural correction vs. brainstorm draft:** an earlier version of this section claimed the script would read `gitlore.prepushCommand` and execute the user's pre-push command. That doesn't match Plan 01's architecture. Plan 01's `gitlore.precommitCommand` is a *prefix-match trigger* read by the PostToolUse CC hook to detect when the user is about to commit — not an executor. The user's actual pre-commit/pre-push commands are run by their hook manager, not by gitlore. Plan 02 follows that pattern: no `gitlore.prepushCommand`.

### 3.2 Failure modes

| State | Behavior |
|---|---|
| Memory `live` ff-pushable, remote reachable | Push succeeds, outer push proceeds |
| Memory push fails: auth expired, network | Hook fails, message: "memory push failed — run `/gitlore:resolve`" |
| Memory `live` diverged from remote (non-ff) | Hook fails, message: "memory's `live` diverged from remote — run `/gitlore:resolve`" |
| Memory submodule has no remote (corrupted post-install state) | Hook fails, message: "memory submodule has no remote — run `/gitlore:resolve`" |

### 3.3 Idempotency

The pre-push hook is read-only on the local memory repo (it pushes, doesn't commit). Re-running it is safe.

### 3.4 Implementation notes for writing-plans

- **Wrapper file already exists.** Plan 01's emitter writes `.git/gitlore-pre-push`, but Plan 01 only created a no-op stub for the underlying hook script at `scripts/git-hooks/pre-push` (exits 0). Plan 02 replaces that stub with the real implementation.
- **No user-command wrapping.** The pre-push hook only pushes memory. The user's pre-push commands are the hook manager's responsibility.

---

## 4. Phase B — Remote creation flow

### 4.1 When it runs

During `/gitlore:install`, after the memory submodule is created and staged, before install reports success. Idempotent on re-run: if the memory submodule already has `remote.origin.url`, the section is a no-op.

### 4.2 Pre-flight gate

Before any destructive operation:

- `gh --version` must succeed
- `gh auth status` must succeed

Either failure aborts install immediately with a one-line fix-up message, having modified *nothing* in the target repo. The pre-flight gate is the only way Phase B can fail without entering recovery via `/gitlore:resolve`.

### 4.3 Detection

- `git -C <memory-path> config --get remote.origin.url` returns empty → proceed to creation.
- Non-empty → skip Phase B (idempotent re-run path).

### 4.4 Creation

- Owner: `gh api user -q .login` — the authenticated user's namespace. Does not require the target repo to exist on GitHub.
- Repo name: `<target-repo-name>-gitlore-memory`.
- Visibility: `--private`. Memory content may carry context the user wouldn't publish.
- Command: `gh repo create <owner>/<name> --private --source=<memory-path> --push`.
- `--push` handles the initial `live` branch push as part of creation. (Verify `gh repo create --source` behavior with submodule-relative paths during implementation; may need to `cd` into the memory worktree first.)

### 4.5 Failure modes

| State | Behavior |
|---|---|
| Pre-flight: `gh` missing | Abort install, repo untouched, message points to gh install + re-run install |
| Pre-flight: `gh` unauthed | Abort install, repo untouched, message points to `gh auth login` + re-run install |
| `gh repo create` fails: name collision | Install exits non-zero, route to `/gitlore:resolve` |
| `gh repo create` fails: API/network | Install exits non-zero, route to `/gitlore:resolve` |
| `gh repo create` succeeded but `--push` failed | Repo exists on GitHub but empty; local submodule has `origin.url` set; `/gitlore:resolve` retries push |
| Mid-install crash (kill -9, power loss) | Indeterminate partial state; `/gitlore:resolve` diagnoses and recovers |

### 4.6 Implementation footprint

- New file: `scripts/install/create-remote.sh` — the remote-creation logic, callable from both install and resolve.
- Modify: `scripts/install/run.sh` — invoke pre-flight, then `create-remote.sh`, after submodule init.
- Modify: existing install bats suite — add fixtures that mock `gh`.

---

## 5. Testing strategy — outside-in TDD

### 5.1 Order of work (also the task order for Plan 02)

1. Write red e2e happy-path test → fails because Phase A + Phase B code doesn't exist.
2. Drive units to green: each unit test exists because the e2e couldn't reach further.
3. Backfill failure-case unit tests for branches the happy-path e2e didn't force.
4. **🐕 Dogfood A** — install Plan 02's pre-push hook on the gitlore repo itself; push `origin/main`; verify memory's `live` ff-pushes; outer push proceeds only if memory push succeeded. Any surprise patches Phase A before Phase B begins.
5. Implement Phase B (driven by the install e2e).
6. Backfill Phase B failure-case unit tests.
7. **🐕 Dogfood B** — run `/gitlore:install` on the gitmoji repo. One command, end-to-end: install → pre-flight → submodule → remote creation → working pre-commit hook. Any surprise patches Phase B.

Dogfood gates are plan execution steps, not afterthoughts. Plan 02 is not considered shipped until both have been run and any surprises patched.

### 5.2 Two e2e tests, one per user-facing contract

| Test | Contract under test | Scenario |
|---|---|---|
| `install` e2e | Phase B: one-command install wires everything | Fresh repo, `gh` mock available + authed → run `/gitlore:install` → assert memory submodule created+staged, remote configured, `live` branch pushed, both hooks installed |
| `commit-and-push` e2e | Phase A: pre-push hook propagates memory | Post-install repo → make a commit (pre-commit fires, memory commit created) → `git push` (pre-push fires, memory's `live` ff-pushes) → assert remote `live` advanced to match local |

Both are **black-box**: they shell out to the user-facing commands and inspect repo state, never reach into intermediate functions. Aligns with the outside-in-TDD principle: tests survive refactors because they couple to the contract, not the implementation.

### 5.3 `gh` fixturing

Default to a mocked `gh` on `$PATH` for both bats suites — a script that records calls and returns scripted responses. Real `gh` against real GitHub is what Dogfood B validates.

Rationale: keeps CI fast and hermetic; keeps the "did the contract hold for reality" question explicitly in the dogfood gate where it belongs. Tests verify the contract held against the `gh` interface; dogfood verifies `gh` itself behaves as expected.

### 5.4 Failure-case unit tests (after happy-path green)

- Pre-flight: `gh` missing → install aborts, repo untouched, exit non-zero with fix-up message.
- Pre-flight: `gh` unauthed → same behavior.
- Detection: existing `remote.origin.url` → Phase B section is a no-op.
- Creation: `gh repo create` fails → install exits with routing message pointing to `/gitlore:resolve`.
- Creation: repo created but `--push` failed → install exits with routing message.
- Re-run after partial install state → idempotent / picks up where it left off.

### 5.5 Test layout

- New `tests/install_remote.bats` — install e2e + remote-creation unit cases.
- Extend existing `tests/install_run.bats` only for shared pre-flight assertions.
- New `tests/pre_push_hook.bats` — pre-push contract + failure modes.
- New `tests/resolve.bats` — `/gitlore:resolve` detection + dispatch.

---

## 6. Failure modes and `/gitlore:resolve` routing

### 6.1 `/gitlore:resolve` — the recovery command

A new CC slash command (markdown file) that invokes a shell script doing all detection and dispatch logic. Per the project principle "agent executes, scripts decide" ([[feedback-agent-executes]]), the agent doesn't reason about repair — the script decides, the agent reports.

### 6.2 Detection order (script)

1. Memory submodule exists? If no → "gitlore not installed, run `/gitlore:install`".
2. Memory submodule has `remote.origin.url`? If no → invoke the shared remote-creation code path (same one Phase B calls).
3. Remote reachable? (`git -C <memory-path> ls-remote` succeeds?) If no → "check network or `gh auth status`".
4. Local `live` exists on remote? If no → push local `live` (recovery for "created but `--push` failed").
5. Local `live` ff-relationship to remote? If diverged → report divergence, point user at manual resolution (Plan 02 does *not* auto-resolve divergence).

### 6.3 Scope boundary for `/gitlore:resolve` in Plan 02

**Handles:** missing remote, unreachable remote, unpushed remote, name-collision dispatch (during a fresh Phase B attempt), partial install state.

**Defers to later plans:** auto-resolving non-ff divergence, force-push prompts, multi-repo recovery, GitHub Enterprise endpoints.

### 6.4 Implementation footprint

- New file: `commands/gitlore/resolve.md` — CC slash command stub that invokes the shell script.
- New file: `scripts/resolve.sh` — detection + dispatch logic.
- New file: `scripts/install/create-remote.sh` (introduced in 4.6) is callable from both `scripts/install/run.sh` and `scripts/resolve.sh`. Single source of truth for remote creation, designed shared from day one rather than retrofitted later.

---

## File layout (additions / modifications)

```
commands/gitlore/resolve.md                 # NEW — /gitlore:resolve command
scripts/install/create-remote.sh            # NEW — shared remote-creation logic
scripts/install/preflight.sh                # NEW — gh + auth checks
scripts/install/run.sh                      # MODIFY — invoke preflight + create-remote
scripts/git-hooks/pre-push                  # NEW — real pre-push hook (replaces Plan 01 stub)
scripts/resolve.sh                          # NEW — detection + dispatch for /gitlore:resolve
tests/install_remote.bats                   # NEW — install e2e + remote-creation unit cases
tests/pre_push_hook.bats                    # NEW — pre-push contract
tests/resolve.bats                          # NEW — /gitlore:resolve detection + dispatch
tests/helpers/gh-mock.bash                  # NEW — gh mocking utilities
```

---

## Open questions resolved during writing-plans

1. ~~**`gh repo create --source` with submodule paths.**~~ Resolved: run `gh repo create` from inside the memory worktree (`git -C "$mempath"`), with `--source=.`. Avoids relative-path ambiguity.
2. ~~**Mid-install crash recovery diagnosis.**~~ Resolved: `/gitlore:resolve` uses the detection order in Section 6.2 — each step is a discrete state probe. Partial install is the case where step 1 passes but step 2 fails; partial creation is step 2 passes but step 4 fails.
3. ~~**`gh-mock.bash` interface.**~~ Resolved: per-test scripted responses. Tests `export` env vars that the mock reads to decide its behavior. See Task 1.
4. ~~**Submodule URL after remote creation.**~~ Resolved: `create-remote.sh` rewrites `.gitmodules` after a successful `gh repo create` and re-stages it. See Task 8.

---

# Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Plan 01's pre-push no-op stub with a real memory-push hook, and extend `/gitlore:install` to create a GitHub remote for the memory submodule (gated by a pre-flight check). Add `/gitlore:resolve` for recovery from partial / broken remote state.

**Architecture:** `bash` shell scripts orchestrated by Claude Code commands and git hooks. The remote-creation logic lives in `scripts/install/create-remote.sh` and is called by both `scripts/install/run.sh` (during install) and `scripts/resolve.sh` (during recovery). Single source of truth.

**Tech stack:** `bash` (target 3.2+), `bats-core` for tests, `jq`/`gh` at runtime, POSIX `git`. Test mocks for `gh` via a per-test scripted shim on `$PATH`.

---

## File layout (target end state of this plan)

```
commands/gitlore/resolve.md              # NEW — /gitlore:resolve CC command
scripts/install/preflight.sh             # NEW — gh + auth checks
scripts/install/create-remote.sh         # NEW — shared remote-creation logic
scripts/install/run.sh                   # MODIFY — invoke preflight + create-remote
scripts/git-hooks/pre-push               # MODIFY — replace stub with real push
scripts/resolve.sh                       # NEW — detection + dispatch for /gitlore:resolve
tests/helpers/gh-mock.bash               # NEW — per-test gh mocking
tests/pre_push_hook.bats                 # NEW — Phase A contract + failures
tests/install_remote.bats                # NEW — Phase B contract + failures
tests/resolve.bats                       # NEW — /gitlore:resolve detection + dispatch
```

---

## Conventions for every task

- Same as Plan 01 (`docs/plans/2026-05-15-01-local-memory-pipeline.md`): bats files load `helpers/setup`, scripts begin with `#!/usr/bin/env bash` + `set -euo pipefail`, library functions namespaced `gitlore_<verb>_<noun>`, hook scripts exit 0 (silent ok) or 1 (loud failure), commit prefix per gitmoji convention.
- Tests use the `gh-mock.bash` helper (Task 1) for any test that would otherwise hit real `gh`. Tests *never* hit the real GitHub API — that's what Dogfood B is for.

---
## Task 1: Pre-push hook end-to-end

**Files:**
- Create: `tests/pre_push_hook.bats`
- Modify: `scripts/git-hooks/pre-push` (replaces Plan 01's no-op stub)

Outside-in TDD: write the happy-path e2e first → drive the script to green → backfill failure-case tests. All in one task because the failure cases share setup and the implementation handles them in a single branchy path.

- [x] **Step 1: Write the happy-path test.**

Create `tests/pre_push_hook.bats`:

```bash
#\!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  # Add a memory commit so we have something to push.
  (
    cd memory
    git checkout -q live
    echo new-fact > FACT.md
    git add FACT.md
    git commit -q -m "Add fact"
  )
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "pre-push pushes memory live to its origin" {
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  local_sha=$(git -C memory rev-parse live)
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  [ "$local_sha" = "$remote_sha" ]
}
```

- [x] **Step 2: Run to confirm red.**

Run: `bats tests/pre_push_hook.bats`
Expected: 1 failure — the stub exits 0 without pushing, so the SHA comparison fails.

- [x] **Step 3: Replace the stub with the real implementation.**

`scripts/git-hooks/pre-push`:

```bash
#\!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.path" >/dev/null 2>&1 || exit 0

mempath=$(gitlore_memory_path)

remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ]; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory submodule has no remote configured. Run /gitlore:resolve to create one." \
    "gitlore: memory submodule has no remote configured. Open this project in Claude Code and run /gitlore:resolve." >&2
  exit 1
fi

if \! git -C "$mempath" push -q origin live 2>/dev/null; then
  if git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory's live branch diverged from remote (non-fast-forward). Run /gitlore:resolve." \
      "gitlore: memory's live branch diverged from remote. Open this project in Claude Code and run /gitlore:resolve." >&2
  else
    gitlore_say_for_agent_or_user \
      "gitlore: memory remote unreachable. Check network or 'gh auth status', then retry. Run /gitlore:resolve if the issue persists." \
      "gitlore: memory remote unreachable. Check network or 'gh auth status', then retry." >&2
  fi
  exit 1
fi

exit 0
```

- [x] **Step 4: Run happy-path; confirm green.**

Run: `bats tests/pre_push_hook.bats`
Expected: 1 passing.

- [x] **Step 5: Append failure-case tests.**

```bash
@test "pre-push fails with /gitlore:resolve hint when memory has no remote" {
  git -C memory remote remove origin
  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]] || [[ "${output}${stderr}" == *"no remote"* ]]
}

@test "pre-push fails with divergence hint when remote diverged" {
  (
    cd "$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    echo remote-only > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only commit"
    git push -q origin live
  )
  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"diverged"* ]] || [[ "${output}${stderr}" == *"/gitlore:resolve"* ]]
}

@test "pre-push fails when remote is unreachable" {
  git -C memory remote set-url origin /this/path/does/not/exist.git
  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"unreachable"* ]] || [[ "${output}${stderr}" == *"network"* ]]
}

@test "pre-push is a no-op when no submodule registered" {
  rm -f .gitmodules
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 6: Run; confirm all green.**

Run: `bats tests/pre_push_hook.bats`
Expected: 5 passing. The implementation from Step 3 already handles all four failure paths — no further edits needed.

- [x] **Step 7: Commit.**

```bash
git add scripts/git-hooks/pre-push tests/pre_push_hook.bats
git commit -m "✨ feat: pre-push hook pushes memory live and routes failures to /gitlore:resolve"
```

---

## Task 2: 🐕 Dogfood A — pre-push hook on the gitlore repo itself

**Files:** none (manual validation).

The gitlore repo already has a memory submodule with a real remote. The new `scripts/git-hooks/pre-push` becomes active automatically because `gitlore.hooksDir` already points at this plugin's `scripts/git-hooks/`.

- [x] **Step 1: Make a memory-affecting change (or skip if memory is already ahead of remote).**

Edit a memory file so the next commit produces a memory commit, or check `git -C memory log live ^origin/live` to see if local is already ahead.

- [x] **Step 2: Trigger a parent push.**

```bash
git -C /Users/david/code/gitlore push origin main
```

- [x] **Step 3: Observe the pre-push hook running.**

Expected: memory's `live` is pushed to its remote before the parent push proceeds. If the memory push fails (auth, network, divergence), the parent push aborts with the routing message.

- [x] **Step 4: Patch any surprises before starting Task 3.**

Any deviation from expected behavior is a Phase A patch, not a Phase B concern. Patch, commit, re-run this dogfood, then proceed. Do not start install-remote work with a broken pre-push.

- [x] **Step 5: If patches were needed, write a feedback memory.**

Capture what the fixture suite missed. Commit with `📝 memory: ...`.

---

## Task 3: Install remote creation end-to-end

**Files:**
- Create: `tests/helpers/gh-mock.bash` — per-test `gh` shim
- Create: `tests/gh_mock.bats` — sanity tests for the mock itself
- Create: `tests/install_remote.bats` — install e2e + preflight + failure-case tests
- Create: `scripts/install/preflight.sh` — gh + auth checks
- Create: `scripts/install/create-remote.sh` — shared remote-creation logic
- Modify: `scripts/install/run.sh` — invoke preflight + create-remote
- Modify: `tests/install_run.bats` if Plan 01's tests break under the new preflight gate

Outside-in TDD: write red e2e for the full install-with-remote flow → implement preflight (it gates everything) → implement create-remote → wire into `run.sh` → backfill failure-case tests.

- [x] **Step 1: Build the `gh` mock helper.**

Create `tests/helpers/gh-mock.bash`:

```bash
#\!/usr/bin/env bash
# Per-test gh mock. Call install_gh_mock from setup(). Scripture behavior:
#   GH_MOCK_EXIT, GH_MOCK_STDOUT, GH_MOCK_STDERR, GH_MOCK_LOG
# Per-subcommand overrides: GH_MOCK_EXIT_REPO_CREATE, GH_MOCK_STDOUT_API_USER, etc.
# (uppercase, _-joined first two args.)

install_gh_mock() {
  local bindir="$TMP_REPO/.gh-mock-bin"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'EOF'
#\!/usr/bin/env bash
if [ -n "${GH_MOCK_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GH_MOCK_LOG"
fi

sub=$(printf '%s_%s' "${1:-}" "${2:-}" | tr 'a-z-' 'A-Z_')
override_exit_var="GH_MOCK_EXIT_${sub}"
override_stdout_var="GH_MOCK_STDOUT_${sub}"
override_stderr_var="GH_MOCK_STDERR_${sub}"

exit_code="${\!override_exit_var:-${GH_MOCK_EXIT:-0}}"
stdout_val="${\!override_stdout_var:-${GH_MOCK_STDOUT:-}}"
stderr_val="${\!override_stderr_var:-${GH_MOCK_STDERR:-}}"

if [ -z "$stdout_val" ] && [ "${1:-}" = "--version" ]; then
  stdout_val="gh version mock 0.0.0 (mock build)"
fi

[ -n "$stdout_val" ] && printf '%s\n' "$stdout_val"
[ -n "$stderr_val" ] && printf '%s\n' "$stderr_val" >&2
exit "$exit_code"
EOF
  chmod +x "$bindir/gh"
  export PATH="$bindir:$PATH"
}
```

- [x] **Step 2: Sanity-test the mock.**

Create `tests/gh_mock.bats`:

```bash
#\!/usr/bin/env bats

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  install_gh_mock
}
teardown() { teardown_tmp_repo; }

@test "gh mock: returns success by default" {
  run gh --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh version mock"* ]]
}

@test "gh mock: GH_MOCK_EXIT scripts exit code" {
  GH_MOCK_EXIT=2 run gh auth status
  [ "$status" -eq 2 ]
}

@test "gh mock: GH_MOCK_STDOUT_API_USER scripts per-subcommand stdout" {
  GH_MOCK_STDOUT_API_USER="alice" run gh api user -q .login
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "gh mock: records calls to GH_MOCK_LOG" {
  log="$TMP_REPO/calls.log"
  GH_MOCK_LOG="$log" gh repo create foo --private
  grep -q 'repo create foo --private' "$log"
}
```

Run: `bats tests/gh_mock.bats` — expect 4 passing. (If failing, fix the mock before continuing.)

- [x] **Step 3: Write red e2e for install remote-creation.**

Create `tests/install_remote.bats`:

```bash
#\!/usr/bin/env bats

load helpers/setup
load helpers/gh-mock

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
}
teardown() { teardown_tmp_repo; }

@test "install configures memory submodule remote via gh repo create" {
  bash "$RUN_INSTALL" memory "echo precommit"
  url=$(git -C memory config --get remote.origin.url 2>/dev/null || true)
  [ -n "$url" ]
}

@test "install rewrites .gitmodules URL from placeholder to real remote" {
  bash "$RUN_INSTALL" memory "echo precommit"
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" \!= *"gitlore-placeholder"* ]]
}

@test "install records gh repo create call with --private --source=. --push" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  grep -q 'repo create' "$log"
  grep -q -- '--private' "$log"
  grep -q -- '--push' "$log"
}
```

Run: `bats tests/install_remote.bats` — expect 3 failures (install doesn't do remote creation yet).

- [x] **Step 4: Implement preflight.**

Create `scripts/install/preflight.sh`:

```bash
#\!/usr/bin/env bash
# Exit 0 if gh is available and authenticated; non-zero with a fix-up
# message on stderr otherwise. Must do no destructive work.
set -euo pipefail

if \! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' CLI not found. Install it from https://cli.github.com/, then re-run /gitlore:install.
EOF
  exit 1
fi

if \! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' is not authenticated. Run 'gh auth login', then re-run /gitlore:install.
EOF
  exit 1
fi

exit 0
```

- [x] **Step 5: Implement create-remote.**

Create `scripts/install/create-remote.sh`:

```bash
#\!/usr/bin/env bash
# Create the memory submodule's GitHub remote and rewire .gitmodules.
# Idempotent: no-op when remote.origin.url is already a real URL.
# Args: $1 = mempath (relative to repo root)
set -euo pipefail

mempath="$1"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

existing=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" \!= "./.git/gitlore-placeholder" ]; then
  exit 0
fi

owner=$(gh api user -q .login)
repo_basename=$(basename "$(git rev-parse --show-toplevel)")
repo_name="${repo_basename}-gitlore-memory"
full_name="${owner}/${repo_name}"

(
  cd "$mempath"
  git checkout -q live
  if \! gh repo create "$full_name" --private --source=. --push 2>&1; then
    echo "gitlore: gh repo create failed. Run /gitlore:resolve to recover." >&2
    exit 1
  fi
)

new_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$new_url" ]; then
  echo "gitlore: gh repo create succeeded but remote.origin.url is empty. Run /gitlore:resolve." >&2
  exit 1
fi

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$new_url"
git add .gitmodules

exit 0
```

- [x] **Step 6: Wire preflight + create-remote into `scripts/install/run.sh`.**

Modify `scripts/install/run.sh`:

- Insert preflight as the first action after the `cd`-into-repo-root guard, before the "Refuse non-empty existing path" check:

  ```bash
  bash "$PLUGIN_ROOT/scripts/install/preflight.sh"
  ```

- Insert create-remote after `init-submodule.sh` and before `write-settings.sh`:

  ```bash
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  ```

Final ordering inside `run.sh`:
1. Repo-root guard
2. Pre-flight (NEW)
3. Existing "refuse non-empty path" check
4. `init-submodule.sh`
5. `create-remote.sh` (NEW)
6. `write-settings.sh`
7. `emit-wrappers.sh`
8. Hook manager wiring
9. Final `git add` of tracked artifacts
10. Echo "install complete"

- [x] **Step 7: Run happy-path tests; confirm green.**

Run: `bats tests/install_remote.bats`
Expected: 3 passing.

- [x] **Step 8: Verify Plan 01's install tests still pass.**

Run: `bats tests/install_run.bats`
Expected: all of Plan 01's install tests still pass.

If any fail because they didn't set up the gh mock, modify `tests/install_run.bats` to `load helpers/gh-mock` and call `install_gh_mock` + `export GH_MOCK_STDOUT_API_USER="alice"` in setup. Plan 02's preflight now requires a working `gh` even in Plan 01's test paths.

- [x] **Step 9: Append failure-case tests.**

Append to `tests/install_remote.bats`:

```bash
@test "preflight aborts install when gh is missing" {
  PATH="$(echo "$PATH" | sed "s|$TMP_REPO/.gh-mock-bin:||")" \
    run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"gh"* ]]
  [ \! -d memory ]
  [ \! -f .claude/settings.json ]
}

@test "preflight aborts install when gh is unauthed" {
  GH_MOCK_EXIT_AUTH_STATUS=1 run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"gh auth login"* ]]
  [ \! -d memory ]
  [ \! -f .claude/settings.json ]
}

@test "install aborts cleanly when gh repo create fails (name collision)" {
  GH_MOCK_EXIT_REPO_CREATE=1 \
    GH_MOCK_STDERR_REPO_CREATE="GraphQL: Name already exists on this account" \
    run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]]
}

@test "install is idempotent (no second gh repo create call on re-run)" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  count=$(grep -c 'repo create' "$log" || true)
  [ "$count" -eq 1 ]
}
```

- [x] **Step 10: Run; confirm all green.**

Run: `bats tests/install_remote.bats`
Expected: 7 passing.

- [x] **Step 11: Commit.**

```bash
git add tests/helpers/gh-mock.bash tests/gh_mock.bats tests/install_remote.bats \
        scripts/install/preflight.sh scripts/install/create-remote.sh scripts/install/run.sh \
        tests/install_run.bats
git commit -m "✨ feat: install creates memory submodule remote via gh, gated by preflight"
```

---

## Task 4: `/gitlore:resolve` — command, script, and tests

**Files:**
- Create: `commands/gitlore/resolve.md` — CC slash command
- Create: `scripts/resolve.sh` — detection + dispatch logic
- Create: `tests/resolve.bats` — detection + dispatch tests

The command file is a thin shim. The real work happens in `scripts/resolve.sh`. Tests drive the script.

- [x] **Step 1: Write failing tests.**

Create `tests/resolve.bats`:

```bash
#\!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/gh-mock

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
}
teardown() { teardown_tmp_repo; }

@test "resolve: errors when no memory submodule registered" {
  run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"not installed"* ]] || [[ "$output$stderr" == *"/gitlore:install"* ]]
}

@test "resolve: creates remote when memory has no origin.url" {
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q 'repo create' "$log"
  [ -n "$(git -C memory config --get remote.origin.url)" ]
}

@test "resolve: reports unreachable remote without calling gh repo create" {
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin /does/not/exist.git
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"unreachable"* ]] || [[ "$output$stderr" == *"network"* ]] || [[ "$output$stderr" == *"auth"* ]]
  \! grep -q 'repo create' "$log" 2>/dev/null
}

@test "resolve: pushes live when remote exists but has no live branch" {
  make_parent_with_memory
  bare="$TMP_REPO/.recover-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  remote_live=$(git --git-dir="$bare" rev-parse live 2>/dev/null || echo MISSING)
  [ "$remote_live" \!= "MISSING" ]
}

@test "resolve: no-op when healthy" {
  make_parent_with_memory
  bare="$TMP_REPO/.healthy-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  git -C memory push -q origin live
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  \! grep -q 'repo create' "$log" 2>/dev/null
}
```

Run: `bats tests/resolve.bats` — expect 5 failures.

- [x] **Step 2: Implement `scripts/resolve.sh`.**

```bash
#\!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

# Step 1: gitlore installed?
if \! gitlore_has_submodule; then
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
fi

mempath=$(gitlore_memory_path)

# Step 2: remote.origin.url set?
remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ] || [ "$remote_url" = "./.git/gitlore-placeholder" ]; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  exit 0
fi

# Step 3: remote reachable?
if \! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'. Manual fix required." \
    "gitlore: memory remote unreachable. Check network or run 'gh auth status'." >&2
  exit 1
fi

# Step 4: live exists on remote?
if \! git -C "$mempath" ls-remote origin live | grep -q .; then
  echo "gitlore: remote has no live branch. Pushing." >&2
  git -C "$mempath" push origin live
  echo "gitlore: live pushed." >&2
  exit 0
fi

# Step 5: ff-relationship between local and remote live?
local_live=$(git -C "$mempath" rev-parse live)
remote_live=$(git -C "$mempath" ls-remote origin live | awk '{print $1}')
if [ "$local_live" \!= "$remote_live" ]; then
  if git -C "$mempath" merge-base --is-ancestor "$remote_live" "$local_live"; then
    echo "gitlore: local live is ahead of remote. Pushing." >&2
    git -C "$mempath" push origin live
    echo "gitlore: live pushed." >&2
    exit 0
  fi
  gitlore_say_for_agent_or_user \
    "gitlore: local and remote live diverged. Manual resolution required — Plan 02 does not auto-resolve divergence. Inspect with 'git -C $mempath log live..origin/live' and 'git -C $mempath log origin/live..live'." \
    "gitlore: local and remote live diverged. Open the memory submodule and resolve manually." >&2
  exit 1
fi

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
```

- [x] **Step 3: Run; confirm green.**

Run: `bats tests/resolve.bats`
Expected: 5 passing.

- [x] **Step 4: Write the CC command file.**

Create `commands/gitlore/resolve.md`:

```markdown
---
description: Diagnose and recover from a partial or broken gitlore remote setup
allowed-tools: ["Bash"]
---

# /gitlore:resolve

You are recovering a gitlore install whose memory remote is missing, unreachable, or partially configured.

## Steps

1. **Confirm context.** Run `git rev-parse --show-toplevel`. If this fails, tell the user to cd into a git repo and abort.

2. **Run the resolver script.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
   ```

   Exits 0 on success (state healthy or repaired). Non-zero means manual intervention is needed; surface stderr verbatim and stop.

3. **Summarize.** Tell the user what state was detected and what action was taken (or what they need to do next).
```

- [x] **Step 5: Commit.**

```bash
git add scripts/resolve.sh tests/resolve.bats commands/gitlore/resolve.md
git commit -m "✨ feat: /gitlore:resolve detection, dispatch, and command"
```

---

## Task 5: 🐕 Dogfood B — install on the gitmoji repo

**Files:** none (manual validation).

End-to-end: one `/gitlore:install` command on a virgin repo. Tests the full Plan 01 + Plan 02 happy path against real `gh` and a real GitHub remote.

- [x] **Step 1: Locate the gitmoji repo and verify virgin state.**

The user will identify the path. Verify it has:
- A `.git/` directory
- No existing `memory/` submodule
- No existing `.claude/settings.json` with `gitlore.enabled`

- [x] **Step 2: Run `/gitlore:install`.**

From inside Claude Code, navigate to the gitmoji repo root and invoke:

```
/gitlore:install memory "lefthook run pre-commit"
```

Adapt the precommit command to whatever the gitmoji repo actually uses; or pick a sensible no-op like `echo`.

- [x] **Step 3: Observe the install flow.**

Expected, in order:
1. Preflight passes (gh + auth ok).
2. Memory submodule created at `memory/`.
3. `gh repo create <user>/gitmoji-gitlore-memory --private --source=. --push` succeeds.
4. `.gitmodules` URL points at the real remote (not the placeholder).
5. `.claude/settings.json`, `.claude/gitlore-hook-setup`, `.gitignore` are staged.
6. Memory submodule is staged as a gitlink (mode 160000).
7. Install completes with "Review the staged changes" message.

- [x] **Step 4: Exercise the full pipeline.**

Make a memory-affecting change, commit (pre-commit fires, memory commit created), then push (pre-push fires, memory's `live` pushes to remote).

- [x] **Step 5: Patch any surprises.**

Any deviation is a Plan 02 patch. Patch, commit, re-run. Plan 02 is not shipped until this works end-to-end.

- [x] **Step 6: Write a `feedback_dogfood_b.md` memory.**

Record what *did* surface as a second concrete instance of [[feedback-dogfood-early]].

---

## Self-review checklist (writing-plans)

- ✅ Spec coverage: Sections 2.1's three bullets (Phase A, Phase B, `/gitlore:resolve`) each have dedicated tasks. Sections 3, 4, 5, 6 each map to specific tasks or test files.
- ✅ Placeholder scan: no TBDs, no "add appropriate error handling", no "similar to Task N", no references to undefined symbols.
- ✅ Type consistency: `mempath`, `GITLORE_SUBMODULE_NAME` (from Plan 01's `scripts/lib/util.sh`), `gitlore_has_submodule`, `gitlore_memory_path` all used consistently.
- ✅ Outside-in test order: each code task writes failing tests first, drives to green, backfills failures within the same task.
- ✅ Single source of truth for remote creation: `create-remote.sh` called from both `install/run.sh` (Task 3) and `resolve.sh` (Task 4).
- ✅ Dogfood gates explicit: Task 2 between Phase A and Phase B; Task 5 after Phase B before plan is considered shipped.
- ✅ Spec corrections inline: removed stale `gitlore.prepushCommand` claim, clarified that user pre-push commands are the hook manager's responsibility.
