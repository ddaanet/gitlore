# Standalone Memory-Commit Entry Point Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a blessed, callable gitlore entry point (`scripts/commit-memory.sh`) that commits the memory submodule and advances local `live` without a parent commit, so an interactive skill can satisfy the FR11 approval gate up front and later non-interactive commits never trip it.

**Architecture:** Factor `pre-commit`'s commit-and-advance-live body into one lib function `gitlore_sync_memory_to_live` (in `scripts/lib/resolve.sh`); both `pre-commit` and the new arg-driven `commit-memory.sh` call it. Callers discover the script via a `gitlore.commitCommand` git config key, re-pinned every `SessionStart` and seeded at install. See design.md D16.

**Tech Stack:** Bash (`set -euo pipefail`), git submodules, bats-core (bats 1.5.0+, `tests/helpers/{setup,fixtures}.bash`).

---

## File Structure

- **Modify** `scripts/lib/resolve.sh` — add `gitlore_sync_memory_to_live MEMPATH`, the factored commit/advance/divergence body.
- **Modify** `scripts/git-hooks/pre-commit` — delegate its body (lines 27–90) to the new lib function; keep only prologue + lib sourcing + presence guards.
- **Create** `scripts/commit-memory.sh` — arg-driven (`-m` / `-F <file>` / `-F -`) entry point; writes the summary to the commit-msg IPC file, then calls the lib function.
- **Modify** `scripts/cc-hooks/session-start.sh` — re-pin `gitlore.commitCommand` next to `gitlore.hooksDir` (line 64 region).
- **Modify** `scripts/install/write-settings.sh` — seed `gitlore.commitCommand` next to `gitlore.hooksDir` (line 36 region).
- **Create** `tests/commit_memory.bats` — entry-point behavior.
- **Modify** `tests/cc_hook_session_start.bats` — assert the re-pinned key.
- **Modify** `tests/install_run.bats` — assert the seeded key.

Run the whole suite with `bats tests/` from the repo root. Run one file with `bats tests/commit_memory.bats`.

---

### Task 1: Factor the commit-and-advance-live body into a lib function

Extract `pre-commit`'s stale-merge precheck + dirty/freshness/commit + push/divergence (lines 27–90) into `gitlore_sync_memory_to_live` so both the hook and the new script share one implementation. The existing `git_hook_pre_commit.bats` suite is the regression net; one direct lib test pins the function's contract.

**Files:**
- Modify: `scripts/lib/resolve.sh` (append new function)
- Modify: `scripts/git-hooks/pre-commit:19-90`
- Test: `tests/git_hook_pre_commit.bats` (existing, must stay green) + `tests/commit_memory.bats` (created in Task 2 also exercises it)

- [ ] **Step 1: Add the function to `scripts/lib/resolve.sh`**

Append at end of file. This is a verbatim relocation of `pre-commit:27-90` with `exit N` → `return N` and `mempath` taken as `$1`:

```bash

# Commit dirty memory with the blessed sentinel and fast-forward local `live`.
# Assumes the memory worktree exists (caller guards `[ -e "$mempath/.git" ]`).
# Returns 0 on success or no-op. Returns 1 after emitting a directive when:
#   a stale merge state is present, memory is dirty without a fresh approved
#   commit-msg file, or the `HEAD:live` fast-forward fails (branch-vs-live
#   divergence). Source the util/log/resolve libs before calling.
# Args: $1 = memory worktree path.
gitlore_sync_memory_to_live() {
  local mempath="$1"

  # Stale merge-state precheck: never commit on top of a half-finished merge.
  local state_status
  state_status=$(gitlore_detect_stale_merge_state "$mempath")
  case "$state_status" in
    stale-with-merge-head)
      local statefile flavor
      statefile=$(gitlore_merge_state_file "$mempath")
      flavor=$(jq -r .flavor "$statefile")
      gitlore_emit_merge_directive "$statefile" "$flavor" "abort-then-retry"
      return 1
      ;;
    stale-no-merge-head)
      local statefile
      statefile=$(gitlore_merge_state_file "$mempath")
      echo "gitlore: merge state file present without MERGE_HEAD — manual intervention required. Inspect $statefile and the memory worktree." >&2
      return 1
      ;;
  esac

  local msgfile dirty live_sha head_sha
  msgfile=$(gitlore_commit_msg_file "$mempath")
  dirty=$(gitlore_memory_dirty "$mempath")
  live_sha=$(git -C "$mempath" rev-parse live 2>/dev/null || echo "")
  head_sha=$(git -C "$mempath" rev-parse HEAD)

  if [ "$dirty" = "0" ] && [ "$head_sha" = "$live_sha" ]; then
    return 0
  fi

  if [ "$dirty" = "1" ]; then
    local fresh
    fresh=$(gitlore_commit_msg_freshness "$mempath")
    if [ "$fresh" != "yes" ]; then
      gitlore_say_for_agent_or_user \
        "gitlore: memory is dirty and has no approved commit summary. Prepare a summary, present it for user confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to $msgfile, then retry." \
        "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
      return 1
    fi
    gitlore_git -C "$mempath" add -A
    # Blessed commit: carry the sentinel so the submodule gate (memory-pre-commit)
    # admits it. A naked commit never sets this and is blocked (FR11/D12).
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile"
    rm -f "$msgfile"
  fi

  if [ -n "$live_sha" ]; then
    if ! gitlore_git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
      # ff-push failed → branch-vs-live divergence. Prepare and yield.
      local prep_out branch base statefile
      if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
        gitlore_say_for_agent_or_user \
          "gitlore: cannot checkout live (already checked out elsewhere). Another session is resolving memory. Wait and retry." \
          "gitlore: another session is resolving memory. Wait and retry." >&2
        return 1
      fi
      branch="${prep_out%%:*}"
      base="${prep_out#*:}"
      gitlore_write_merge_state "$mempath" "branch-vs-live" "$base" "$branch" "live" "$branch" "continue-after-branch-merge"
      statefile=$(gitlore_merge_state_file "$mempath")
      gitlore_emit_merge_directive "$statefile" "branch-vs-live" "continue-after-branch-merge"
      return 1
    fi
  fi

  return 0
}
```

- [ ] **Step 2: Rewrite `scripts/git-hooks/pre-commit` to delegate**

Replace the entire file body from line 19 onward (everything after the lib `source` lines) with presence guards + one call. The file becomes:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Git sets GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE in the hook env (relative to
# the parent repo). Any `git -C <submodule> ...` invocation inherits them and
# tries to resolve `.git/index` under the submodule's gitfile, producing
# "fatal: .git/index: index file open failed: Not a directory". Unset before
# touching the submodule.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""

# Not a gitlore repo → nothing to sync.
[ -z "$mempath" ] && exit 0

# D11 corollary: in a session-less worktree the memory submodule worktree may not
# exist yet. Nothing to sync — never block the parent commit.
[ ! -e "$mempath/.git" ] && exit 0

gitlore_sync_memory_to_live "$mempath"
exit $?
```

Note: the original `git config --file .gitmodules … || exit 0` guard (old line 44) is subsumed by `[ -z "$mempath" ] && exit 0` — `gitlore_memory_path` already returns empty when the submodule is unregistered.

- [ ] **Step 3: Run the existing pre-commit suite to verify behavior is preserved**

Run: `bats tests/git_hook_pre_commit.bats`
Expected: PASS — all existing tests green (clean no-op, dirty+fresh commit/push, dirty+no-summary hint, divergence directive, detached HEAD, leaked-GIT_DIR regression, session-less worktree).

- [ ] **Step 4: Run the resolve suite to confirm no lib regression**

Run: `bats tests/resolve.bats tests/resolve_merge_branch.bats tests/lib_util.bats`
Expected: PASS — the new function only adds; existing resolve/util behavior unchanged.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/resolve.sh scripts/git-hooks/pre-commit
git commit -m "refactor: factor commit-and-advance-live into gitlore_sync_memory_to_live"
```

---

### Task 2: Create the `commit-memory.sh` entry point

Arg-driven script that resolves the memory path, writes the approved summary to the commit-msg IPC file, then calls `gitlore_sync_memory_to_live`. TDD: write the bats file first, watch it fail (script absent), then implement.

**Files:**
- Create: `scripts/commit-memory.sh`
- Test: `tests/commit_memory.bats`

- [ ] **Step 1: Write the failing test file `tests/commit_memory.bats`**

```bash
#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

CMD="$PLUGIN_ROOT/scripts/commit-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "exits 0 when gitlore is not configured" {
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory is clean and synced" {
  make_parent_with_memory
  run bash "$CMD"
  [ "$status" -eq 0 ]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
  rm -rf "$WT"
}

@test "refuses dirty memory with no summary, leaving it uncommitted" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved summary"* ]] || \
    [[ "${output}${stderr}" == *"-m"* ]]
  [ -n "$(git -C memory status --porcelain)" ]   # still dirty, nothing committed
}

@test "-m commits dirty memory and advances live without a parent commit" {
  make_parent_with_memory
  parent_head_before=$(git rev-parse HEAD)
  echo dirty > memory/notes.md

  run bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 0 ]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  wt=$(git -C memory rev-parse worktree)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  # The commit-msg IPC file was consumed.
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-commit-msg)" ]
  # No parent commit happened.
  [ "$(git rev-parse HEAD)" = "$parent_head_before" ]
}

@test "-F - reads the summary from a heredoc" {
  make_parent_with_memory
  echo dirty > memory/notes.md

  run bash -c "'$CMD' -F - <<'EOF'
memory: from heredoc
EOF"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: from heredoc" ]
}

@test "exits 1 with merge directive when branch diverged from live" {
  make_parent_with_memory
  (
    cd memory
    git checkout -q live
    echo "live-only" > MEMORY.md
    git commit -aq -m "Diverging commit on live"
    git checkout -q worktree
  )
  echo dirty > memory/notes.md

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" == *"flavor=branch-vs-live"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/commit_memory.bats`
Expected: FAIL — every test errors (`commit-memory.sh` does not exist).

- [ ] **Step 3: Implement `scripts/commit-memory.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point (D16): commit the memory submodule and advance
# local `live` without a parent commit. Arg-driven, git-commit-style:
#   commit-memory.sh -m "<summary>"     # inline
#   commit-memory.sh -F <file>          # read summary from a file
#   commit-memory.sh -F -               # read summary from stdin (heredoc)
# Activation is the gitlore-memory submodule registration (FR12), same gate as
# pre-commit. Discover this script via `git config gitlore.commitCommand`.

# Defensive: a caller's env may carry leaked GIT_* vars (see pre-commit prologue).
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

summary=""
have_summary=0
while [ $# -gt 0 ]; do
  case "$1" in
    -m)
      summary="${2-}"; have_summary=1; shift 2 ;;
    -F)
      if [ "${2-}" = "-" ]; then summary="$(cat)"; else summary="$(cat "${2-}")"; fi
      have_summary=1; shift 2 ;;
    *)
      echo "usage: commit-memory.sh [-m <summary> | -F <file> | -F -]" >&2
      exit 2 ;;
  esac
done

mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""

# Activation: no gitlore-memory submodule → nothing to do.
[ -z "$mempath" ] && exit 0
# Session-less worktree: memory worktree not materialized → nothing to do.
[ ! -e "$mempath/.git" ] && exit 0

# Arg-driven approval: when memory is dirty we need a summary to write into the
# commit-msg IPC file, which satisfies gitlore_sync_memory_to_live's freshness
# gate by construction (written immediately before the commit).
if [ "$(gitlore_memory_dirty "$mempath")" = "1" ]; then
  if [ "$have_summary" = "0" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory is dirty; commit-memory needs an approved summary. Pass it with -m <summary> or -F - (heredoc)." \
      "gitlore: memory has uncommitted changes; run this from Claude Code with an approved summary." >&2
    exit 1
  fi
  msgfile=$(gitlore_commit_msg_file "$mempath")
  printf '%s\n' "$summary" > "$msgfile"
fi

gitlore_sync_memory_to_live "$mempath"
exit $?
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x scripts/commit-memory.sh`
Expected: no output; `test -x scripts/commit-memory.sh` succeeds.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/commit_memory.bats`
Expected: PASS — all 8 tests green.

- [ ] **Step 6: Lint the new script**

Run: `shellcheck scripts/commit-memory.sh`
Expected: no findings (the `SC1091` source-not-followed lines carry inline disables, matching the hooks).

- [ ] **Step 7: Commit**

```bash
git add scripts/commit-memory.sh tests/commit_memory.bats
git commit -m "feat: add commit-memory.sh standalone memory-commit entry point"
```

---

### Task 3: Publish the discovery key `gitlore.commitCommand`

Set the key in both the per-session re-pin (`session-start.sh`, the self-healing one) and the install seed (`write-settings.sh`), each pointing at `$PLUGIN_ROOT/scripts/commit-memory.sh`.

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh:63-64`
- Modify: `scripts/install/write-settings.sh:34-36`
- Test: `tests/cc_hook_session_start.bats`, `tests/install_run.bats`

- [ ] **Step 1: Add the session-start assertion (failing)**

In `tests/cc_hook_session_start.bats`, extend the existing test at line 30 (`"does not write settings.local.json (D10); sets hooksDir and emits wrappers"`). Immediately after the `hooksDir` assertion (line 37) add:

```bash
  [ "$(git config gitlore.commitCommand)" = "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bats tests/cc_hook_session_start.bats -f "sets hooksDir"`
Expected: FAIL — `git config gitlore.commitCommand` is empty, assertion fails.

- [ ] **Step 3: Set the key in `session-start.sh`**

At `scripts/cc-hooks/session-start.sh`, in the "Hook dir + wrappers" block, add the second `git config` line:

```bash
# Hook dir + wrappers.
git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
git config gitlore.commitCommand "$PLUGIN_ROOT/scripts/commit-memory.sh"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"
```

- [ ] **Step 4: Run the session-start suite to verify it passes**

Run: `bats tests/cc_hook_session_start.bats`
Expected: PASS — all tests green, including the new key assertion.

- [ ] **Step 5: Add the install-seed assertion (failing)**

In `tests/install_run.bats`, locate the test that asserts `gitlore.precommitCommand` (line 38) and add, in the same test, after the install run completes:

```bash
  [ "$(git config gitlore.commitCommand)" = "$PLUGIN_ROOT/scripts/commit-memory.sh" ]
```

(If that test does not run the full install through `write-settings.sh`, instead add a focused test that invokes `bash "$PLUGIN_ROOT/scripts/install/write-settings.sh" memory "test-pc"` inside `setup_tmp_repo` and asserts the key. Verify which by reading the test's body first.)

- [ ] **Step 6: Run it to verify it fails**

Run: `bats tests/install_run.bats`
Expected: FAIL — the new `commitCommand` assertion fails (key unset by install).

- [ ] **Step 7: Seed the key in `write-settings.sh`**

At `scripts/install/write-settings.sh`, after the `hooksDir` line (36):

```bash
# Hook dir.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
git config gitlore.hooksDir "${plugin_root}/scripts/git-hooks"
git config gitlore.commitCommand "${plugin_root}/scripts/commit-memory.sh"
```

- [ ] **Step 8: Run the install suite to verify it passes**

Run: `bats tests/install_run.bats`
Expected: PASS — install now seeds `gitlore.commitCommand`.

- [ ] **Step 9: Run the full suite**

Run: `bats tests/`
Expected: PASS — entire suite green (prior count + the new `commit_memory.bats` tests + 2 assertions).

- [ ] **Step 10: Commit**

```bash
git add scripts/cc-hooks/session-start.sh scripts/install/write-settings.sh \
        tests/cc_hook_session_start.bats tests/install_run.bats
git commit -m "feat: publish gitlore.commitCommand discovery key"
```

---

### Task 4: Record the Changelog entry

The design decision (D16) and Architecture subsection already landed in `docs/design.md` during brainstorming. Add the shipped-state Changelog row now that the work exists.

**Files:**
- Modify: `docs/design.md` (Changelog table, top row)

- [ ] **Step 1: Add the Changelog row**

At the top of the Changelog table in `docs/design.md` (just under the header row), add:

```markdown
| 2026-06-12 | **Implemented D16 — standalone memory-commit entry point.** New `scripts/commit-memory.sh` (arg-driven `-m`/`-F`/`-F -`) commits the memory submodule with the `GITLORE_MEMORY_COMMIT` sentinel and advances local `live` without a parent commit. The commit-and-advance-live body is factored out of `pre-commit` into `gitlore_sync_memory_to_live` (`lib/resolve.sh`); both call it. Discovery via a `gitlore.commitCommand` git config key, re-pinned every `SessionStart` and seeded at install (`write-settings.sh`). Freshness gate kept inside the shared body (pre-commit still needs it; the script satisfies it by writing the summary first). Tests: `commit_memory.bats` (8) + session-start/install key assertions. |
```

- [ ] **Step 2: Commit**

```bash
git add docs/design.md
git commit -m "docs: changelog entry for D16 standalone memory-commit entry point"
```

---

## Self-Review

**Spec coverage (design.md D16 + Architecture subsection):**
- Standalone `commit-memory.sh`, arg-driven `-m`/`-F`/`-F -` → Task 2. ✓
- Factor shared body into `gitlore_sync_memory_to_live`, both callers use it → Task 1. ✓
- Sentinel commit + `push HEAD:live` only (origin stays with `pre-push`) → Task 1 function body (unchanged from pre-commit). ✓
- Freshness gate kept inside, satisfied-by-construction in the script → Task 1 (gate in function) + Task 2 (writes msgfile before calling). ✓
- Graceful no-op guards (not gitlore / no submodule / worktree absent / clean) → Task 2 guards + Task 1 clean-and-synced early return; tested. ✓
- Divergence reuse (prepare/write-state/emit-directive/exit 1) → Task 1 function body; tested in both suites. ✓
- Discovery via `gitlore.commitCommand`, re-pinned at SessionStart + seeded at install → Task 3. ✓
- Activation gate = `.gitmodules` submodule (FR12), not settings.json → Task 2 uses `gitlore_memory_path`; no settings.json read. ✓
- Caller wiring out of scope → no handoff/commit-commands changes in this plan. ✓

**Placeholder scan:** No TBD/TODO. Step 5 of Task 3 contains one conditional ("if that test does not run the full install…") — resolved by reading the test body first, with both branches specified, so it is not an open placeholder.

**Type/name consistency:** `gitlore_sync_memory_to_live` (defined Task 1, called Tasks 1 & 2). `gitlore.commitCommand` and `$PLUGIN_ROOT/scripts/commit-memory.sh` identical across Tasks 2, 3, 4. Function returns 0/1 matching `exit $?` in both callers. Memory branch is `worktree` and trunk is `live` per `make_parent_with_memory`. ✓
