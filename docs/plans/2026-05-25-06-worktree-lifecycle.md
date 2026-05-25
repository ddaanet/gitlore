# Plan 06 — Worktree Lifecycle (SessionStart create-side + WorktreeRemove cleanup)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement task-by-task with TDD (red → green → commit). Steps use `- [ ]` checkboxes. Each step lists exact files, code, and commands.

**Goal:** Make gitlore's per-worktree memory branches track Claude Code's worktree lifecycle — create the memory submodule worktree lazily at `SessionStart` in a linked worktree, and clean it up advisorily on `WorktreeRemove`.

**Architecture:** No `WorktreeCreate` hook (verified an override hook — fires pre-creation, must emit only the worktree path on stdout, no branch in stdin, hangs on extra stdout). Instead, the create-side is handled at `SessionStart` in the new worktree, which already fires there (`claude --worktree` starts a new session) and already mirrors the parent branch name. The remove-side is a new advisory `WorktreeRemove` command hook that removes the memory submodule worktree; the branch is left in place (CC keeps the parent branch on removal — verified). See `docs/design.md` "Worktree creation — handled by `SessionStart`" and "`WorktreeRemove`".

**Tech Stack:** Bash (`set -euo pipefail`), `jq` (hook stdin parsing), `git worktree`, `bats` tests. Verified against git 2.47.3 and CC 2.1.150.

---

## File structure

| File | Change | Responsibility |
|------|--------|----------------|
| `scripts/cc-hooks/session-start.sh` | modify | Add the linked-worktree branch: when `<wt>/<mempath>/.git` is absent **and** the shared submodule gitdir exists, create the memory worktree via `git -C <mem-gitdir> worktree add`. Existing main-worktree `submodule update --init` path stays as the `else`. |
| `scripts/cc-hooks/worktree-remove.sh` | **create** | Advisory `WorktreeRemove` hook: parse `worktree_path` from stdin, remove `<worktree_path>/<mempath>` from the memory submodule's worktree list; prune if already gone; warn (never block) if dirty/locked. |
| `hooks/hooks.json` | modify | Register `WorktreeRemove` → `worktree-remove.sh`. |
| `tests/cc_hook_session_start.bats` | modify | Add a test: linked worktree gets its memory worktree created on the parent-named branch. |
| `tests/cc_hook_worktree_remove.bats` | **create** | Cover the remove hook: clean removal, parent-dir-already-gone, dirty-warns, no-op guards, and hooks.json registration. |
| `Makefile` | modify | Add `tests/cc_hook_worktree_remove.bats` to the `test-unit` list. |
| `docs/plans/2026-05-25-06-worktree-lifecycle.md` | (this file) | Mark steps `[x]` as they land; record dogfood findings. |

Note: `docs/design.md` was already updated during brainstorming (the WorktreeCreate/WorktreeRemove rewrite, Coexistence bullet, Rejected-Alternatives row, changelog — commit `930fbaa`). `docs/plugin-readme.md` has no worktree section, so no readme change is needed.

---

## Task 1: SessionStart creates the memory worktree in a linked worktree

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh:70-72`
- Test: `tests/cc_hook_session_start.bats`

- [ ] **Step 1: Write the failing test.** Append to `tests/cc_hook_session_start.bats`. The fixture builds the parent + memory submodule (main worktree on `worktree` branch), then adds a *linked* parent worktree on a new branch `feat-x` whose `memory/` dir is empty (git does not recurse submodules into new worktrees). SessionStart in that worktree must create the memory worktree on `feat-x`.

  ```bash
  @test "creates the memory worktree in a linked (CC-created) worktree on the parent-named branch" {
    make_parent_with_memory
    WT="$TMP_REPO-wt"
    git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
    # git populates the gitlink dir but does not check out the submodule:
    [ ! -e "$WT/memory/.git" ]
    mkdir -p "$WT/.claude"
    printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"

    CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 run bash "$SESSION_START"
    [ "$status" -eq 0 ]
    [ -e "$WT/memory/.git" ]
    run git -C "$WT/memory" rev-parse --abbrev-ref HEAD
    [ "$output" = "feat-x" ]
  }
  ```

  Also add cleanup for the sibling worktree by replacing this file's `teardown()` (line 9) with:

  ```bash
  teardown() {
    [ -n "${WT:-}" ] && rm -rf "$WT"
    teardown_tmp_repo
  }
  ```

- [ ] **Step 2: Run the test to verify it fails.**

  Run: `bats tests/cc_hook_session_start.bats -f "linked"`
  Expected: FAIL — `$WT/memory/.git` is still absent after SessionStart (the current code's `git submodule update --init` does not create the linked-worktree submodule tree), so the `[ -e "$WT/memory/.git" ]` assertion fails.

- [ ] **Step 3: Implement the linked-worktree branch.** In `scripts/cc-hooks/session-start.sh`, replace the current init block (lines 70-72):

  ```bash
  if [ ! -f "$mempath/.git" ] && [ ! -d "$mempath/.git" ]; then
    git submodule update --init -- "$mempath" >&2
  fi
  ```

  with:

  ```bash
  # Memory working tree missing in this worktree. Two cases:
  #  - submodule never initialized (main worktree, fresh clone) → submodule update;
  #  - submodule initialized in the main repo but this is a *linked* worktree whose
  #    memory tree was never checked out → create it from the shared submodule gitdir.
  # Plain `git submodule update --init` does not reliably populate a submodule in a
  # linked worktree, so the linked case uses an explicit `git worktree add`.
  if [ ! -e "$mempath/.git" ]; then
    common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
    mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
    if [ -d "$mem_gitdir" ]; then
      git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true
      git -C "$mem_gitdir" worktree add --detach "$PWD/$mempath" live >&2
    else
      git submodule update --init -- "$mempath" >&2
    fi
  fi
  ```

  The subsequent checkout block (now ~lines 78-90) is unchanged: it sees the freshly added detached worktree, finds no `refs/heads/feat-x`, and runs `git -C "$mempath" checkout -q -b "$parent_branch" live`, landing the worktree on `feat-x`. (`GITLORE_SUBMODULE_NAME` is already in scope via `source scripts/lib/util.sh`.)

- [ ] **Step 4: Run the test to verify it passes.**

  Run: `bats tests/cc_hook_session_start.bats`
  Expected: PASS — all existing tests plus the new linked-worktree test. (Existing tests use the main worktree where `memory/.git` is present, so the new branch is skipped and their behavior is unchanged.)

- [ ] **Step 5: Commit.**

  ```bash
  git add scripts/cc-hooks/session-start.sh tests/cc_hook_session_start.bats
  git commit -m "feat: SessionStart creates the memory worktree in a linked worktree"
  ```

---

## Task 2: WorktreeRemove advisory cleanup hook

**Files:**
- Create: `scripts/cc-hooks/worktree-remove.sh`
- Test: `tests/cc_hook_worktree_remove.bats`

- [ ] **Step 1: Write the failing tests.** Create `tests/cc_hook_worktree_remove.bats`. The helper sets up a parent + a linked worktree whose memory worktree is already checked out (simulating a prior session), then drives the hook with JSON on stdin.

  ```bash
  #!/usr/bin/env bats

  load helpers/setup
  load helpers/fixtures

  WT_REMOVE="$PLUGIN_ROOT/scripts/cc-hooks/worktree-remove.sh"

  setup() { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
  teardown() {
    [ -n "${WT:-}" ] && rm -rf "$WT"
    teardown_tmp_repo
  }

  # Build a parent + a linked worktree on feat-x whose memory worktree is checked out.
  # Sets $WT (parent worktree path) and $MEM_GITDIR (shared submodule gitdir).
  _make_linked_with_memory() {
    make_parent_with_memory
    WT="$TMP_REPO-wt"
    git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
    MEM_GITDIR="$TMP_REPO/.git/modules/gitlore-memory"
    git -C "$MEM_GITDIR" worktree add -q --detach "$WT/memory" live
    git -C "$WT/memory" checkout -q -b feat-x live
  }

  @test "no-op (exit 0) when .gitmodules has no gitlore-memory entry" {
    printf '{"worktree_path":"/nope"}' | \
      env CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$WT_REMOVE"
  }

  @test "no-op (exit 0) when stdin has no worktree_path" {
    make_parent_with_memory
    printf '{}' | env CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$WT_REMOVE"
  }

  @test "removes the memory worktree when the parent worktree dir is gone" {
    _make_linked_with_memory
    git -C "$MEM_GITDIR" worktree list | grep -qF "$WT/memory"
    rm -rf "$WT"   # simulate CC deleting the parent worktree (incl. memory subdir)
    printf '{"worktree_path":"%s"}' "$WT" | \
      env CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$WT_REMOVE"
    run git -C "$MEM_GITDIR" worktree list
    [[ "$output" != *"$WT/memory"* ]]
  }

  @test "removes a clean memory worktree while the dir still exists" {
    _make_linked_with_memory
    printf '{"worktree_path":"%s"}' "$WT" | \
      env CLAUDE_PROJECT_DIR="$TMP_REPO" bash "$WT_REMOVE"
    run git -C "$MEM_GITDIR" worktree list
    [[ "$output" != *"$WT/memory"* ]]
  }

  @test "warns and leaves a dirty memory worktree in place (never force-removes)" {
    _make_linked_with_memory
    echo "uncommitted" > "$WT/memory/MEMORY.md"
    run --separate-stderr bash -c \
      "printf '{\"worktree_path\":\"$WT\"}' | env CLAUDE_PROJECT_DIR='$TMP_REPO' bash '$WT_REMOVE'"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"$WT/memory"* ]]
    [ -e "$WT/memory/.git" ]
    git -C "$MEM_GITDIR" worktree list | grep -qF "$WT/memory"
  }

  @test "WorktreeRemove is registered in hooks.json pointing at the script" {
    run jq -e '.hooks.WorktreeRemove[0].hooks[0].command
      | test("worktree-remove\\.sh$")' "$PLUGIN_ROOT/hooks/hooks.json"
    [ "$status" -eq 0 ]
  }
  ```

- [ ] **Step 2: Run the tests to verify they fail.**

  Run: `bats tests/cc_hook_worktree_remove.bats`
  Expected: FAIL — `worktree-remove.sh` does not exist (every test errors on the missing script) and the hooks.json registration test fails (no `WorktreeRemove` key yet).

- [ ] **Step 3: Write the hook.** Create `scripts/cc-hooks/worktree-remove.sh`:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

  # shellcheck disable=SC1091
  source "$PLUGIN_ROOT/scripts/lib/util.sh"

  # Operate from the main project (the worktree being removed may already be gone).
  cd "$PROJECT_DIR" 2>/dev/null || exit 0

  # Guard: no-op if this repo doesn't use gitlore.
  gitlore_has_submodule || exit 0

  # WorktreeRemove stdin carries only worktree_path (verified CC 2.1.150).
  input=$(cat)
  worktree_path=$(printf '%s' "$input" | jq -r '.worktree_path // empty')
  [ -n "$worktree_path" ] || exit 0

  mempath=$(gitlore_memory_path)
  mem_wt="$worktree_path/$mempath"

  # Shared submodule gitdir lives under the main repo's common dir.
  common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
  mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
  [ -d "$mem_gitdir" ] || exit 0

  # Advisory cleanup — never block parent worktree removal, never --force
  # (forcing would discard uncommitted memory changes).
  if ! git -C "$mem_gitdir" worktree remove "$mem_wt" >/dev/null 2>&1; then
    if [ ! -e "$mem_wt" ]; then
      # Parent worktree (and its memory subdir) already deleted — drop the stale entry.
      git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true
    else
      echo "gitlore: could not remove memory worktree at $mem_wt (locked or uncommitted changes); leaving it in place." >&2
    fi
  fi

  # Branch retention is a no-op: CC leaves the parent branch in place on removal,
  # so the memory branch is kept too (falls to the normal merged-branch sweep).
  exit 0
  ```

  `chmod 755 scripts/cc-hooks/worktree-remove.sh`.

- [ ] **Step 4: Register the hook.** In `hooks/hooks.json`, add a `WorktreeRemove` entry alongside `SessionStart`/`PostToolUse`:

  ```json
      "WorktreeRemove": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/worktree-remove.sh"
            }
          ]
        }
      ]
  ```

  (No `matcher` — worktree events are not tool-matched. Place the new key inside the existing `"hooks": { … }` object; mind the trailing comma on the preceding entry.)

- [ ] **Step 5: Run the tests to verify they pass.**

  Run: `bats tests/cc_hook_worktree_remove.bats`
  Expected: PASS (all 6 tests).

- [ ] **Step 6: Commit.**

  ```bash
  git add scripts/cc-hooks/worktree-remove.sh hooks/hooks.json tests/cc_hook_worktree_remove.bats
  chmod 755 scripts/cc-hooks/worktree-remove.sh
  git commit -m "feat: advisory WorktreeRemove hook cleans up the memory worktree"
  ```

---

## Task 3: Register the new test file; full suite green

**Files:**
- Modify: `Makefile:6`

- [ ] **Step 1: Add the test file to `test-unit`.** In `Makefile` line 6, append to the `bats` file list:

  ```
   tests/cc_hook_worktree_remove.bats
  ```

  (Append to the existing space-separated list on that line, after `tests/global_shim.bats`.)

- [ ] **Step 2: Run the full suite.**

  Run: `make test`
  Expected: PASS — all unit tests (now including `cc_hook_worktree_remove.bats`) and the integration test.

- [ ] **Step 3: Commit.**

  ```bash
  git add Makefile
  git commit -m "test: register cc_hook_worktree_remove.bats in the suite"
  ```

---

## Task 4: Dogfood in this repo (the real target)

Per "dogfood early" — this repo is the production target. Exercise the full create→remove cycle against the live plugin (under `--plugin-dir`, per the stale-cache lesson).

- [ ] **Step 1: Create a CC worktree and confirm the memory worktree.** From this repo, run `claude --worktree dogfood-06` (or `git worktree add ../gitlore-wt-06 -b dogfood-06` then start a session there). In the new worktree's session, confirm:
  - `ls -la memory/.git` → present (a gitlink file).
  - `git -C memory rev-parse --abbrev-ref HEAD` → `dogfood-06` (the memory branch mirrors the parent branch).
  - `git -C .git/modules/gitlore-memory worktree list` (from the main repo) lists the new worktree's `memory` path on `dogfood-06`.

- [ ] **Step 2: Remove the worktree and confirm cleanup.** Remove the worktree the way CC does (or `git worktree remove ../gitlore-wt-06`). Confirm:
  - `git -C .git/modules/gitlore-memory worktree list` no longer lists the removed worktree's memory path (the `WorktreeRemove` hook pruned it). If removal was via CC, this proves the hook fired; if via plain `git`, run the hook's logic manually to confirm cleanup, and note that plain `git worktree remove` does not fire CC hooks.
  - The `dogfood-06` memory branch still exists (`git -C .git/modules/gitlore-memory branch --list dogfood-06`) — branch retention is a no-op by design.

- [ ] **Step 3: Record findings** in this plan under each step, fix any surprises in-plan, then commit (docs only):

  ```bash
  git add docs/plans/2026-05-25-06-worktree-lifecycle.md
  git commit -m "docs: record Plan 06 dogfood findings"
  ```

---

## Scope

- **In:** `SessionStart` linked-worktree memory-worktree creation; advisory `WorktreeRemove` hook + `hooks.json` registration; bats coverage for both; Makefile registration; self-dogfood. (`docs/design.md` was updated during brainstorming, commit `930fbaa`.)
- **Out:** any `WorktreeCreate` hook (verified the wrong tool — see design "Why not a `WorktreeCreate` hook"); subagent/agent-team ephemeral worktrees (auto-cleaned, no persistent memory — the `WorktreeRemove` hook no-ops on them since no memory worktree was created); mid-session live branch-switch tracking (no CC hook exists; handled at the next `SessionStart`); the smaller deferred items (clone-from-remote smoke, `plugin.json`↔`marketplace.json` version-sync CI, Plan-02 `ddaanet/gitmoji-gitlore-memory` cleanup).

## Open decisions during execution

- **Two worktrees on the same parent branch name.** If `feat-x` is checked out in another memory worktree, the SessionStart checkout block's `git checkout feat-x` fails (git's one-checkout-per-branch rule). This is a pre-existing limitation of the branch model, not introduced here; note it if it surfaces in dogfood, but do not expand scope to handle it.
- **`WorktreeRemove` cwd assumption.** The hook resolves `.gitmodules` and the submodule gitdir from `CLAUDE_PROJECT_DIR`. If a session ever removes the very worktree it is running in (so `CLAUDE_PROJECT_DIR` is gone), the `cd … || exit 0` guard makes it a clean no-op and the stale entry is swept by a later `worktree prune`. Confirm `CLAUDE_PROJECT_DIR` is set for `WorktreeRemove` during dogfood; if it is not, fall back to deriving the main repo from `worktree_path` via `git -C "$worktree_path" rev-parse --git-common-dir` before the dir is gone.
