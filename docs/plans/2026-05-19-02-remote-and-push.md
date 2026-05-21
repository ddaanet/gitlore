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

1. The pre-push wrapper at `.git/gitlore-pre-push` invokes `$(git config gitlore.hooksDir)/pre-push`.
2. That script reads `gitlore.prepushCommand` from git config and runs the user-provided command first (if set). Naming mirrors Plan 01's `gitlore.precommitCommand`. Final symbol verified during implementation — see Open Questions.
3. Then the script pushes the memory submodule's `live` branch to its `origin` (ff-only).
4. If both succeed, the wrapper exits 0 and the outer push proceeds.
5. If either fails, the wrapper exits non-zero with an actionable message routed (where applicable) to `/gitlore:resolve`.

### 3.2 Failure modes

| State | Behavior |
|---|---|
| Memory `live` ff-pushable, remote reachable | Push succeeds, outer push proceeds |
| Memory push fails: auth expired, network | Hook fails, message: "memory push failed — run `/gitlore:resolve`" |
| Memory `live` diverged from remote (non-ff) | Hook fails, message: "memory's `live` diverged from remote — run `/gitlore:resolve`" |
| Memory submodule has no remote (corrupted post-install state) | Hook fails, message: "memory submodule has no remote — run `/gitlore:resolve`" |
| User-provided pre-push command fails | Hook fails with that command's exit code + output; memory push is not attempted |

### 3.3 Idempotency

The pre-push hook is read-only on the local memory repo (it pushes, doesn't commit). Re-running it is safe.

### 3.4 Implementation notes for writing-plans

- **Wrapper file already exists.** Plan 01's emitter (Task 9) already writes `.git/gitlore-pre-push`, but Plan 01 never wired its underlying hook script — Plan 02 must add `scripts/git-hooks/pre-push`.

(Config-key verification moved to the global Open Questions section.)

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

## Open questions for writing-plans

1. **Config key naming for the user's pre-push wrapper.** `gitlore.prepushCommand`? Confirm against design.md and existing conventions.
2. **`gh repo create --source` with submodule paths.** Test whether `--source=<memory-path>` works when run from the parent repo root, or whether the install script needs to `cd` into the memory worktree first.
3. **Mid-install crash recovery diagnosis.** What state markers does `/gitlore:resolve` use to detect "partial install"? Likely: presence of memory submodule + absence of either `remote.origin.url` or unpushed `live`. Spell out in the implementation plan.
4. **`gh-mock.bash` interface.** Should mocked `gh` return canned JSON, or accept scripted responses per test? Lean toward per-test scripting for failure-mode coverage.
