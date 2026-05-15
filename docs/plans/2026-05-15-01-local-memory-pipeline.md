# gitlore Plan 01 — Local Memory Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user can install gitlore in a parent repo and get a working local memory submodule with agent-driven commits. No remote, no resolve, no Claude-Code-initiated worktrees yet.

**Architecture:** A Claude Code plugin (manifest + commands + hooks + shell library). Detection and branching logic lives in `bash` scripts. The plugin scaffolds a git submodule named `gitlore-memory`, wires git hooks (pre-commit/pre-push) into the parent repo via the user's hook manager, and uses Claude Code hooks (`SessionStart`, `PostToolUse`) to keep state coherent.

**Tech stack:**
- `bash` (target 3.2+ for macOS compat; no GNU-isms unless gated)
- `bats-core` for shell tests
- `jq` for JSON manipulation (settings files, hook stdin)
- `yq` for YAML edits (lefthook, overcommit config) — opportunistic, with sed fallback
- POSIX `git` only

**Scope of this plan:**
- Plugin scaffolding (`plugin.json`, dir layout, settings glue).
- Shared shell utilities for path/branch/state discovery.
- Hook manager detection + wiring for lefthook / husky / overcommit / direct / manual.
- `.git/gitlore-pre-*` wrappers.
- `SessionStart` hook (guards, settings, hooksDir, wrappers, branch model, ff merge, sentinel replay).
- `PostToolUse` hook (commit-message preparation trigger).
- `pre-commit` git hook (commit memory using approved msg file, ff push to `live`, fail-loud on divergence).
- `/gitlore:install` skill — local-only flow (no remote).
- bats integration tests covering install + happy-path commit.

**Out of scope for this plan:**
- Remote creation, `pre-push` hook, push semantics → Plan 02.
- `/gitlore:resolve` and sub-agent synthesis → Plan 03.
- `WorktreeCreate` / `WorktreeRemove` hooks → Plan 04.
- Clone-from-remote smoke test, polish, expanded docs → Plan 05.

**Reference:** `docs/design.md` is the authoritative spec. Where this plan and the design disagree, the design wins; flag the divergence in a PR comment before deviating.

---

## File layout (target end state of this plan)

```
plugin.json
hooks.json                                  # Claude Code hook config (referenced from plugin.json)
commands/gitlore/install.md                 # /gitlore:install slash command
skills/install/SKILL.md                     # invokable skill content for install
scripts/lib/util.sh                         # shared shell utilities (sourced)
scripts/lib/log.sh                          # CLAUDECODE-branched messaging helpers
scripts/hook-manager/detect.sh              # outputs one of: lefthook|husky|overcommit|direct|manual|multi
scripts/hook-manager/wire-lefthook.sh
scripts/hook-manager/wire-husky.sh
scripts/hook-manager/wire-overcommit.sh
scripts/hook-manager/wire-direct.sh
scripts/hook-manager/wire-manual.sh
scripts/emit-wrappers.sh                    # writes .git/gitlore-pre-{commit,push}
scripts/install/run.sh                      # orchestration logic for /gitlore:install
scripts/install/init-submodule.sh           # submodule add + seed + initial commit + branches
scripts/install/write-settings.sh           # writes .claude/settings.{json,local.json}
scripts/cc-hooks/session-start.sh
scripts/cc-hooks/post-tool-use.sh
scripts/git-hooks/pre-commit.sh
tests/helpers/setup.bash                    # bats common setup (mk tmp repo, source libs)
tests/helpers/fixtures.bash                 # parent-repo + memory-submodule factory
tests/lib_util.bats
tests/hook_manager_detect.bats
tests/hook_manager_wire.bats
tests/emit_wrappers.bats
tests/cc_hook_session_start.bats
tests/cc_hook_post_tool_use.bats
tests/git_hook_pre_commit.bats
tests/install_run.bats
tests/integration_happy_path.bats
docs/plugin-readme.md                       # user-facing readme (concise)
.editorconfig
```

Files not yet created appear as "Create:" in the task entries below; modifications appear as "Modify:".

---

## Conventions for every task

- Tests live under `tests/`, run via `bats tests/<file>.bats`.
- All bats files source `tests/helpers/setup.bash`, which sources every `scripts/lib/*.sh`.
- Shell scripts begin with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Library functions are namespaced `gitlore_<verb>_<noun>` (e.g. `gitlore_memory_path`).
- Library functions print results to stdout, errors to stderr, return non-zero on failure.
- Hook scripts exit with `0` (silent no-op), `1` (loud failure with actionable message), never higher.
- All wiring carries a `# gitlore: managed` marker (or YAML key equivalent) for idempotency.
- Commit prefix per project convention: gitmoji (`✨ feat:`, `🐛 fix:`, `🚧 wip:`, `🧪 test:`, `📝 docs:`, `🔧 chore:`, `♻️ refactor:`). Recent commits in this repo use the bare emoji form (`🔧 …`), keep that style.

---

## Task 1: Plugin manifest + directory scaffold

**Files:**
- Create: `plugin.json`
- Create: `hooks.json`
- Create: `commands/gitlore/install.md` (stub placeholder; full content in Task 13)
- Create: `skills/install/SKILL.md` (stub)
- Create: `.editorconfig`
- Create: `docs/plugin-readme.md` (one-paragraph stub; expanded in Plan 05)

- [ ] **Step 1: Author `plugin.json`.**

```json
{
  "name": "gitlore",
  "version": "0.1.0",
  "description": "Versioned, shared, git-backed memory for Claude Code.",
  "homepage": "https://github.com/<owner>/gitlore",
  "hooks": "hooks.json",
  "commands": ["commands/gitlore/install.md"],
  "skills": ["skills/install/SKILL.md"]
}
```

> Verify field names against current Claude Code plugin manifest schema before merging. If `commands`/`skills`/`hooks` arrays are auto-discovered from directories in the installed CC version, drop the explicit lists. The `plugin-dev:plugin-structure` skill is the authoritative reference.

- [ ] **Step 2: Author `hooks.json`.**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/session-start.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/post-tool-use.sh"
          }
        ]
      }
    ]
  }
}
```

> Verify against `plugin-dev:hook-development` for current field names. Adjust if CC uses a different matcher shape.

- [ ] **Step 3: Stub the install command/skill files.**

`commands/gitlore/install.md`:

```markdown
---
description: Install gitlore in this repository
---

(Stub — replaced in Task 13.)
```

`skills/install/SKILL.md`:

```markdown
---
name: gitlore-install
description: Install gitlore memory submodule and wire hooks
---

(Stub — replaced in Task 13.)
```

- [ ] **Step 4: Create `.editorconfig`.**

```ini
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
indent_style = space
indent_size = 2

[*.sh]
indent_size = 2

[Makefile]
indent_style = tab
```

- [ ] **Step 5: Create `docs/plugin-readme.md` stub.**

```markdown
# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the full design. User-facing docs land in Plan 05.
```

- [ ] **Step 6: Verify the plugin loads.**

Run: `ls plugin.json hooks.json commands/gitlore/install.md skills/install/SKILL.md`
Expected: all four paths print.

Optional: `cd /tmp && claude --plugin /Users/david/code/gitlore --help` — if your CC build supports `--plugin`, expect no parse error. Skip if not.

- [ ] **Step 7: Commit.**

```bash
git add plugin.json hooks.json commands/gitlore/install.md skills/install/SKILL.md .editorconfig docs/plugin-readme.md
git commit -m "✨ scaffold gitlore plugin manifest and directory layout"
```

---

## Task 2: bats test harness

**Files:**
- Create: `tests/helpers/setup.bash`
- Create: `tests/helpers/fixtures.bash`
- Create: `tests/smoke.bats`
- Modify: top-level dev docs to mention `bats tests/` (in `docs/plugin-readme.md`).

- [ ] **Step 1: Install bats locally if not present.**

```bash
command -v bats || brew install bats-core 2>/dev/null || npm install -g bats
```

Expected: `bats --version` prints a version ≥ 1.10.

- [ ] **Step 2: Write `tests/helpers/setup.bash`.**

```bash
#!/usr/bin/env bash
# Common bats setup. Source from each .bats file with: `load helpers/setup`.
set -euo pipefail

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
export PLUGIN_ROOT

setup_tmp_repo() {
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name  "Test"
}

teardown_tmp_repo() {
  if [ -n "${TMP_REPO:-}" ] && [ -d "$TMP_REPO" ]; then
    rm -rf "$TMP_REPO"
  fi
}

# Load every script under scripts/lib so library functions are in scope.
for f in "$PLUGIN_ROOT"/scripts/lib/*.sh; do
  # shellcheck disable=SC1090
  [ -f "$f" ] && source "$f"
done
```

- [ ] **Step 3: Write `tests/helpers/fixtures.bash`.**

```bash
#!/usr/bin/env bash
# Factories for common test fixtures.

# Create a parent repo with a memory submodule pointing at a local bare repo.
# Args: $1 = memory subpath (default "memory")
make_parent_with_memory() {
  local subpath="${1:-memory}"
  local bare="$TMP_REPO/.bare-memory.git"
  git init -q --bare "$bare"
  git submodule add "$bare" "$subpath" >/dev/null 2>&1
  (
    cd "$subpath"
    git config user.email "test@example.com"
    git config user.name  "Test"
    echo "# memory" > MEMORY.md
    git add MEMORY.md
    git commit -q -m "Initial memory"
    git branch live
    git branch worktree
    git checkout -q worktree
  )
  git add .gitmodules "$subpath"
  git commit -q -m "Add memory submodule"
}
```

- [ ] **Step 4: Write a smoke test that verifies the harness itself.**

`tests/smoke.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "smoke: harness creates a clean parent repo" {
  [ -d "$TMP_REPO/.git" ]
  run git rev-parse --is-inside-work-tree
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "smoke: fixture creates parent with memory submodule" {
  make_parent_with_memory
  [ -f .gitmodules ]
  run git config --file .gitmodules submodule.memory.path
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}
```

- [ ] **Step 5: Run the smoke test.**

Run: `bats tests/smoke.bats`
Expected: 2 passing tests.

- [ ] **Step 6: Commit.**

```bash
git add tests/helpers/setup.bash tests/helpers/fixtures.bash tests/smoke.bats
git commit -m "🧪 add bats test harness and smoke tests"
```

---

## Task 3: Shared shell utilities — discovery functions

**Files:**
- Create: `scripts/lib/util.sh`
- Create: `tests/lib_util.bats`

- [ ] **Step 1: Write failing tests for `gitlore_memory_path`.**

`tests/lib_util.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "gitlore_memory_path returns empty when no .gitmodules" {
  run gitlore_memory_path
  [ "$status" -ne 0 ]
}

@test "gitlore_memory_path reads from .gitmodules using gitlore-memory submodule name" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = memory
  url = ./bare.git
EOF
  run gitlore_memory_path
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}

@test "gitlore_memory_path supports custom subpath" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = .claude/memory
  url = ./bare.git
EOF
  run gitlore_memory_path
  [ "$status" -eq 0 ]
  [ "$output" = ".claude/memory" ]
}

@test "gitlore_has_submodule returns 1 when missing" {
  run gitlore_has_submodule
  [ "$status" -eq 1 ]
}

@test "gitlore_has_submodule returns 0 when present" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = memory
  url = ./bare.git
EOF
  run gitlore_has_submodule
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to see them fail.**

Run: `bats tests/lib_util.bats`
Expected: 5 failures, "gitlore_memory_path: command not found" or similar.

- [ ] **Step 3: Implement `scripts/lib/util.sh`.**

```bash
#!/usr/bin/env bash
# Shared shell utilities. Source; do not exec.

# The canonical submodule name regardless of working-tree path.
GITLORE_SUBMODULE_NAME="gitlore-memory"
readonly GITLORE_SUBMODULE_NAME

# Print the memory submodule's working-tree path (relative to repo root).
# Exit 1 if the submodule is not registered.
gitlore_memory_path() {
  local path
  path=$(git config --file .gitmodules \
    "submodule.${GITLORE_SUBMODULE_NAME}.path" 2>/dev/null) || return 1
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Exit 0 if .gitmodules registers the gitlore-memory submodule, 1 otherwise.
gitlore_has_submodule() {
  gitlore_memory_path >/dev/null 2>&1
}

# Print the parent worktree's branch name, or "DETACHED" if not on a branch.
# Exit 1 outside a git repo.
gitlore_parent_branch() {
  local b
  b=$(git symbolic-ref --short -q HEAD 2>/dev/null) || {
    git rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    printf 'DETACHED\n'
    return 0
  }
  printf '%s\n' "$b"
}

# Print abs path to the memory submodule's commit-msg file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (must exist as a working tree).
gitlore_commit_msg_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-commit-msg
}

# Echo 1 if memory worktree is dirty (uncommitted changes), 0 otherwise.
gitlore_memory_dirty() {
  local mempath="$1"
  if [ -z "$(git -C "$mempath" status --porcelain)" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# Echo "yes" if commit-msg file is fresh (mtime >= newest tracked memory file),
# else "no" or "absent".
gitlore_commit_msg_freshness() {
  local mempath="$1"
  local msgfile
  msgfile=$(gitlore_commit_msg_file "$mempath")
  [ -f "$msgfile" ] || { printf 'absent\n'; return 0; }
  local newest
  newest=$(find "$mempath" -type f -not -path '*/.git/*' -printf '%T@\n' 2>/dev/null \
           | sort -nr | head -1)
  local msgmtime
  msgmtime=$(stat -f '%m' "$msgfile" 2>/dev/null || stat -c '%Y' "$msgfile")
  awk -v a="$msgmtime" -v b="${newest:-0}" \
      'BEGIN { print (a+0 >= b+0) ? "yes" : "no" }'
}
```

> `stat`/`find` flags differ between BSD and GNU. The above tries BSD form first, GNU second. If macOS `find` lacks `-printf`, swap to a portable loop. Add a follow-up sub-task if portability fails on CI.

- [ ] **Step 4: Run tests to verify they pass.**

Run: `bats tests/lib_util.bats`
Expected: 5 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/lib/util.sh tests/lib_util.bats
git commit -m "✨ feat: shared shell utilities for memory path/state discovery"
```

---

## Task 4: Logging helpers (CLAUDECODE-branched messages)

**Files:**
- Create: `scripts/lib/log.sh`
- Modify: `tests/helpers/setup.bash` — picks up the new lib automatically (already globs `scripts/lib/*.sh`).
- Create: `tests/lib_log.bats`

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup

@test "gitlore_say_for_agent_or_user prints agent text when CLAUDECODE set" {
  CLAUDECODE=1 run gitlore_say_for_agent_or_user "AGENT MESSAGE" "USER MESSAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "AGENT MESSAGE" ]
}

@test "gitlore_say_for_agent_or_user prints user text when CLAUDECODE unset" {
  unset CLAUDECODE
  run gitlore_say_for_agent_or_user "AGENT MESSAGE" "USER MESSAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "USER MESSAGE" ]
}
```

- [ ] **Step 2: Run and confirm failure.**

Run: `bats tests/lib_log.bats`
Expected: 2 failures.

- [ ] **Step 3: Implement.**

`scripts/lib/log.sh`:

```bash
#!/usr/bin/env bash
# Branch a message based on whether we're being run inside a Claude Code session.

# Args: $1 = agent-targeted text, $2 = user-targeted text.
# Output goes to stdout for easy capture in tests. Hook scripts redirect to stderr
# at the call site when failing.
gitlore_say_for_agent_or_user() {
  local agent_msg="$1"
  local user_msg="$2"
  if [ -n "${CLAUDECODE:-}" ]; then
    printf '%s\n' "$agent_msg"
  else
    printf '%s\n' "$user_msg"
  fi
}
```

- [ ] **Step 4: Verify.**

Run: `bats tests/lib_log.bats`
Expected: 2 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/lib/log.sh tests/lib_log.bats
git commit -m "✨ feat: CLAUDECODE-branched logging helper"
```

---

## Task 5: Hook manager detection

**Files:**
- Create: `scripts/hook-manager/detect.sh`
- Create: `tests/hook_manager_detect.bats`

Output contract (one of, on stdout, single line):
- `lefthook`
- `husky`
- `overcommit`
- `direct`
- `manual`
- `multi:<a>,<b>` when more than one match — caller decides whether to warn.

Exit always 0.

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

DETECT="$PLUGIN_ROOT/scripts/hook-manager/detect.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "detects lefthook via lefthook.yml" {
  : > lefthook.yml
  run bash "$DETECT"
  [ "$output" = "lefthook" ]
}

@test "detects husky via .husky directory" {
  mkdir .husky
  run bash "$DETECT"
  [ "$output" = "husky" ]
}

@test "detects overcommit via .overcommit.yml" {
  : > .overcommit.yml
  run bash "$DETECT"
  [ "$output" = "overcommit" ]
}

@test "detects direct via executable .git/hooks/pre-commit not owned by a manager" {
  printf '#!/bin/sh\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run bash "$DETECT"
  [ "$output" = "direct" ]
}

@test "returns manual when nothing detected" {
  run bash "$DETECT"
  [ "$output" = "manual" ]
}

@test "reports multi when both lefthook and husky are present" {
  : > lefthook.yml
  mkdir .husky
  run bash "$DETECT"
  [[ "$output" == multi:* ]]
  [[ "$output" == *lefthook* ]]
  [[ "$output" == *husky* ]]
}
```

- [ ] **Step 2: Run and confirm failures.**

Run: `bats tests/hook_manager_detect.bats`
Expected: 6 failures.

- [ ] **Step 3: Implement.**

`scripts/hook-manager/detect.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

detected=()

if [ -f lefthook.yml ] || [ -f .lefthook.yml ]; then
  detected+=("lefthook")
fi
if [ -d .husky ]; then
  detected+=("husky")
fi
if [ -f .overcommit.yml ] || [ -f .git/hooks/overcommit-hook ]; then
  detected+=("overcommit")
fi
if [ -x .git/hooks/pre-commit ] && [ ${#detected[@]} -eq 0 ]; then
  # Direct only if no manager already matched. Most hook managers also drop a
  # .git/hooks/pre-commit shim, but detection precedence runs manager checks first.
  if ! grep -q '# gitlore: managed' .git/hooks/pre-commit 2>/dev/null; then
    detected+=("direct")
  fi
fi

case "${#detected[@]}" in
  0) printf 'manual\n' ;;
  1) printf '%s\n' "${detected[0]}" ;;
  *) printf 'multi:%s\n' "$(IFS=,; echo "${detected[*]}")" ;;
esac
```

- [ ] **Step 4: Verify.**

Run: `bats tests/hook_manager_detect.bats`
Expected: 6 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/hook-manager/detect.sh tests/hook_manager_detect.bats
git commit -m "✨ feat: hook manager detection script"
```

---

## Task 6: Hook manager wiring — lefthook

**Files:**
- Create: `scripts/hook-manager/wire-lefthook.sh`
- Create: `tests/hook_manager_wire.bats` (extended in later wiring tasks)

Idempotency strategy: each wiring adds a `# gitlore: managed` marker comment. Re-runs detect the marker and no-op.

The lefthook wiring appends entries under `pre-commit` and `pre-push` referencing the wrappers at `.git/gitlore-pre-commit` / `.git/gitlore-pre-push`. Use `yq` if available, otherwise a guarded append-block keyed by the marker.

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup

WIRE_LEFTHOOK="$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"

setup() {
  setup_tmp_repo
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
}
teardown() { teardown_tmp_repo; }

@test "wire-lefthook adds gitlore command under pre-commit and pre-push" {
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' lefthook.yml
  grep -q '.git/gitlore-pre-commit' lefthook.yml
  grep -q '.git/gitlore-pre-push' lefthook.yml
}

@test "wire-lefthook is idempotent (marker present → no change)" {
  bash "$WIRE_LEFTHOOK"
  cp lefthook.yml lefthook.yml.before
  bash "$WIRE_LEFTHOOK"
  diff lefthook.yml lefthook.yml.before
}

@test "wire-lefthook writes sentinel file" {
  mkdir -p .claude
  bash "$WIRE_LEFTHOOK"
  [ -f .claude/gitlore-hook-setup ]
  [ "$(cat .claude/gitlore-hook-setup)" = "lefthook install" ]
}
```

- [ ] **Step 2: Run and confirm failures.**

Run: `bats tests/hook_manager_wire.bats`
Expected: 3 failures.

- [ ] **Step 3: Implement.**

`scripts/hook-manager/wire-lefthook.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="lefthook.yml"
[ -f "$CONFIG" ] || CONFIG=".lefthook.yml"
[ -f "$CONFIG" ] || { echo "wire-lefthook: no lefthook config found" >&2; exit 1; }

if grep -q '# gitlore: managed' "$CONFIG"; then
  : # already wired
else
  cat >> "$CONFIG" <<'EOF'

# gitlore: managed
pre-commit:
  commands:
    gitlore:
      run: .git/gitlore-pre-commit
pre-push:
  commands:
    gitlore:
      run: .git/gitlore-pre-push
EOF
fi

mkdir -p .claude
printf 'lefthook install\n' > .claude/gitlore-hook-setup
```

> The naive append-block above merges by relying on lefthook's tolerance for multiple top-level `pre-commit:` keys. **Verify** with the lefthook docs / a sample run. If lefthook errors on duplicate top-level keys, switch to a `yq`-based merge:
>
> ```bash
> yq -i '.pre-commit.commands.gitlore.run = ".git/gitlore-pre-commit"' "$CONFIG"
> yq -i '.pre-push.commands.gitlore.run   = ".git/gitlore-pre-push"'   "$CONFIG"
> ```
>
> Add `yq` as a dependency in the readme if used.

- [ ] **Step 4: Verify.**

Run: `bats tests/hook_manager_wire.bats`
Expected: 3 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/hook-manager/wire-lefthook.sh tests/hook_manager_wire.bats
git commit -m "✨ feat: lefthook wiring with idempotency marker"
```

---

## Task 7: Hook manager wiring — husky

**Files:**
- Create: `scripts/hook-manager/wire-husky.sh`
- Modify: `tests/hook_manager_wire.bats` (add husky tests)

- [ ] **Step 1: Append failing tests.**

```bash
@test "wire-husky appends guarded exec lines to .husky/pre-commit and pre-push" {
  mkdir .husky
  : > .husky/pre-commit
  : > .husky/pre-push
  run bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .husky/pre-commit
  grep -q 'exec .git/gitlore-pre-commit' .husky/pre-commit
  grep -q '# gitlore: managed' .husky/pre-push
  grep -q 'exec .git/gitlore-pre-push' .husky/pre-push
}

@test "wire-husky creates missing pre-* files" {
  mkdir .husky
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"
  [ -f .husky/pre-commit ]
  [ -f .husky/pre-push ]
}

@test "wire-husky is idempotent" {
  mkdir .husky
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"
  cp .husky/pre-commit .husky/pre-commit.before
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"
  diff .husky/pre-commit .husky/pre-commit.before
}

@test "wire-husky writes sentinel" {
  mkdir .husky .claude
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"
  [ "$(cat .claude/gitlore-hook-setup)" = "npx husky" ]
}
```

- [ ] **Step 2: Run; confirm 4 failures.**

Run: `bats tests/hook_manager_wire.bats`

- [ ] **Step 3: Implement.**

`scripts/hook-manager/wire-husky.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

[ -d .husky ] || { echo "wire-husky: no .husky directory" >&2; exit 1; }

for hook in pre-commit pre-push; do
  f=".husky/$hook"
  if [ ! -f "$f" ]; then
    cat > "$f" <<EOF
#!/usr/bin/env sh
EOF
    chmod +x "$f"
  fi
  if ! grep -q '# gitlore: managed' "$f"; then
    cat >> "$f" <<EOF

# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  fi
done

mkdir -p .claude
printf 'npx husky\n' > .claude/gitlore-hook-setup
```

- [ ] **Step 4: Verify.**

Run: `bats tests/hook_manager_wire.bats`
Expected: all (7) passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/hook-manager/wire-husky.sh tests/hook_manager_wire.bats
git commit -m "✨ feat: husky wiring with idempotency marker"
```

---

## Task 8: Hook manager wiring — overcommit, direct, manual

Three smaller wirings bundled into one task; each gets its own bats test block.

**Files:**
- Create: `scripts/hook-manager/wire-overcommit.sh`
- Create: `scripts/hook-manager/wire-direct.sh`
- Create: `scripts/hook-manager/wire-manual.sh`
- Modify: `tests/hook_manager_wire.bats`

- [ ] **Step 1: Append failing tests for all three.**

```bash
@test "wire-overcommit adds gitlore PreCommit and PrePush entries" {
  cat > .overcommit.yml <<'EOF'
PreCommit:
  RuboCop:
    enabled: true
EOF
  run bash "$PLUGIN_ROOT/scripts/hook-manager/wire-overcommit.sh"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .overcommit.yml
  grep -q 'gitlore-pre-commit' .overcommit.yml
  grep -q 'gitlore-pre-push' .overcommit.yml
  [ "$(cat .claude/gitlore-hook-setup)" = "overcommit --install" ]
}

@test "wire-direct installs .git/hooks/pre-commit and pre-push stubs" {
  run bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
  [ "$status" -eq 0 ]
  [ -x .git/hooks/pre-commit ]
  [ -x .git/hooks/pre-push ]
  grep -q 'exec .git/gitlore-pre-commit' .git/hooks/pre-commit
  grep -q '# gitlore: managed' .git/hooks/pre-commit
  [ "$(cat .claude/gitlore-hook-setup)" = "direct" ]
}

@test "wire-direct is idempotent and preserves existing user hooks" {
  printf '#!/bin/sh\necho user hook\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
  grep -q 'echo user hook' .git/hooks/pre-commit
  grep -q 'exec .git/gitlore-pre-commit' .git/hooks/pre-commit
  # Second run: no duplicate lines.
  cp .git/hooks/pre-commit .git/hooks/pre-commit.before
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
  diff .git/hooks/pre-commit .git/hooks/pre-commit.before
}

@test "wire-manual writes a manual sentinel without modifying any files" {
  ls > before.txt
  run bash "$PLUGIN_ROOT/scripts/hook-manager/wire-manual.sh"
  [ "$status" -eq 0 ]
  [ "$(cat .claude/gitlore-hook-setup)" = "manual" ]
  # No new tracked files beyond the sentinel.
  ls | grep -v '^\.claude$' | grep -v '^before.txt$' > after.txt
  diff before.txt after.txt
}
```

- [ ] **Step 2: Run; confirm failures.**

Run: `bats tests/hook_manager_wire.bats`
Expected: 4 new failures.

- [ ] **Step 3: Implement wire-overcommit.**

`scripts/hook-manager/wire-overcommit.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG=".overcommit.yml"
[ -f "$CONFIG" ] || { echo "wire-overcommit: no $CONFIG" >&2; exit 1; }

if ! grep -q '# gitlore: managed' "$CONFIG"; then
  cat >> "$CONFIG" <<'EOF'

# gitlore: managed
PreCommit:
  gitlore:
    enabled: true
    command: ['.git/gitlore-pre-commit']
PrePush:
  gitlore:
    enabled: true
    command: ['.git/gitlore-pre-push']
EOF
fi

mkdir -p .claude
printf 'overcommit --install\n' > .claude/gitlore-hook-setup
```

> Same warning as lefthook: verify overcommit accepts duplicate top-level keys. If not, switch to `yq` or a Ruby helper.

- [ ] **Step 4: Implement wire-direct.**

`scripts/hook-manager/wire-direct.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

for hook in pre-commit pre-push; do
  f=".git/hooks/$hook"
  if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
    continue
  fi
  if [ -f "$f" ]; then
    cat >> "$f" <<EOF

# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  else
    cat > "$f" <<EOF
#!/usr/bin/env sh
# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  fi
  chmod +x "$f"
done

mkdir -p .claude
printf 'direct\n' > .claude/gitlore-hook-setup
```

- [ ] **Step 5: Implement wire-manual.**

`scripts/hook-manager/wire-manual.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .claude
printf 'manual\n' > .claude/gitlore-hook-setup

cat >&2 <<'EOF'
gitlore: no supported hook manager detected.
Wire the wrappers into your hook system manually:

  pre-commit → .git/gitlore-pre-commit
  pre-push   → .git/gitlore-pre-push

Once wired, run /gitlore:install again to re-detect.
EOF
```

- [ ] **Step 6: Verify all four passing.**

Run: `bats tests/hook_manager_wire.bats`
Expected: 11 passing.

- [ ] **Step 7: Commit.**

```bash
git add scripts/hook-manager/wire-overcommit.sh scripts/hook-manager/wire-direct.sh scripts/hook-manager/wire-manual.sh tests/hook_manager_wire.bats
git commit -m "✨ feat: overcommit, direct, and manual hook wiring"
```

---

## Task 9: Wrapper emitter (`.git/gitlore-pre-*`)

**Files:**
- Create: `scripts/emit-wrappers.sh`
- Create: `tests/emit_wrappers.bats`

The wrappers are flat files written to `.git/`. Each delegates to `$(git config gitlore.hooksDir)/<hook>`. If `gitlore.hooksDir` is unset, exit 0 with a stderr hint.

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup

EMIT="$PLUGIN_ROOT/scripts/emit-wrappers.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "emit-wrappers writes both wrapper files and makes them executable" {
  run bash "$EMIT"
  [ "$status" -eq 0 ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}

@test "wrapper exits 0 with hint when gitlore.hooksDir unset" {
  bash "$EMIT"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]] || \
    [[ "$(cat <<<"$output")" == *"gitlore skipped"* ]]
}

@test "wrapper execs the real hook when gitlore.hooksDir set" {
  bash "$EMIT"
  fake="$TMP_REPO/fakehooks"
  mkdir -p "$fake"
  cat > "$fake/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "real-hook-ran"
exit 0
EOF
  chmod +x "$fake/pre-commit"
  git config gitlore.hooksDir "$fake"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"real-hook-ran"* ]]
}

@test "emit-wrappers is idempotent" {
  bash "$EMIT"
  cp .git/gitlore-pre-commit .git/gitlore-pre-commit.before
  bash "$EMIT"
  diff .git/gitlore-pre-commit .git/gitlore-pre-commit.before
}
```

- [ ] **Step 2: Run; confirm 4 failures.**

- [ ] **Step 3: Implement.**

`scripts/emit-wrappers.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

write_wrapper() {
  local hook="$1"
  local out=".git/gitlore-$hook"
  cat > "$out" <<EOF
#!/usr/bin/env sh
HOOKS_DIR=\$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "\$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
exec "\$HOOKS_DIR/$hook" "\$@"
EOF
  chmod +x "$out"
}

write_wrapper pre-commit
write_wrapper pre-push
```

- [ ] **Step 4: Verify.**

Run: `bats tests/emit_wrappers.bats`
Expected: 4 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/emit-wrappers.sh tests/emit_wrappers.bats
git commit -m "✨ feat: emit .git/gitlore-pre-* wrappers"
```

---

## Task 10: SessionStart hook — guards, settings, hooksDir, wrappers

**Files:**
- Create: `scripts/cc-hooks/session-start.sh`
- Create: `tests/cc_hook_session_start.bats`

CC SessionStart hook receives JSON on stdin (per CC hook docs). For Plan 01 we only need to know it ran in the parent repo's root — we'll `cd "$CLAUDE_PROJECT_DIR"` if exported, else use cwd.

Guards (in order):
1. If `.claude/settings.json` does not exist or `gitlore.enabled` is not `true` → exit 0.
2. If `.gitmodules` has no `gitlore-memory` entry → exit 0.

Effects when both guards pass:
- Write `autoMemoryDirectory` (abs path) to `.claude/settings.local.json`.
- `git config gitlore.hooksDir "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks"`.
- Run `scripts/emit-wrappers.sh`.

> Branch model side effects (submodule init, ff merge, reserved-name check) come in Task 11. Sentinel replay comes in Task 12. Splitting keeps each task within the 2–5 min/step rule.

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() { teardown_tmp_repo; }

@test "no-op when gitlore.enabled is missing" {
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "no-op when .gitmodules has no gitlore-memory entry" {
  mkdir .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "writes autoMemoryDirectory and hooksDir and emits wrappers" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -f .claude/settings.local.json ]
  grep -q autoMemoryDirectory .claude/settings.local.json
  [ "$(git config gitlore.hooksDir)" = "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks" ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}
```

- [ ] **Step 2: Run; confirm 3 failures.**

- [ ] **Step 3: Implement.**

`scripts/cc-hooks/session-start.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# Guard 1: gitlore.enabled
enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json 2>/dev/null || echo false)
[ "$enabled" = "true" ] || exit 0

# Guard 2: gitlore-memory submodule registered
gitlore_has_submodule || exit 0

mempath=$(gitlore_memory_path)
absmem=$(cd "$mempath" 2>/dev/null && pwd || echo "$PROJECT_DIR/$mempath")

# Update settings.local.json (create or merge).
mkdir -p .claude
if [ -f .claude/settings.local.json ]; then
  tmp=$(mktemp)
  jq --arg p "$absmem" '.autoMemoryDirectory = $p' .claude/settings.local.json > "$tmp"
  mv "$tmp" .claude/settings.local.json
else
  printf '{"autoMemoryDirectory":"%s"}\n' "$absmem" > .claude/settings.local.json
fi

# Hook dir + wrappers.
git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"
```

Also drop a placeholder so `scripts/git-hooks/pre-commit` exists (real impl arrives in Task 17). For now create an empty executable stub:

```bash
mkdir -p scripts/git-hooks
cat > scripts/git-hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x scripts/git-hooks/pre-commit
cp scripts/git-hooks/pre-commit scripts/git-hooks/pre-push
```

- [ ] **Step 4: Verify.**

Run: `bats tests/cc_hook_session_start.bats`
Expected: 3 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/cc-hooks/session-start.sh scripts/git-hooks/pre-commit scripts/git-hooks/pre-push tests/cc_hook_session_start.bats
git commit -m "✨ feat: SessionStart writes settings, wires hooksDir, emits wrappers"
```

---

## Task 11: SessionStart — branch model + ff merge

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh`
- Modify: `tests/cc_hook_session_start.bats`

Behavior to add:
- If memory submodule not initialized → `git submodule update --init`.
- Determine target branch:
  - Parent branch is `live` → **reject**, exit 1 with branched message.
  - Parent on `DETACHED` → memory must also be on `DETACHED` (mirroring `live` tip).
  - Otherwise → use parent branch name.
- If target branch doesn't exist on the memory side → create from `live`.
- Switch memory worktree to target branch.
- If memory worktree is clean → `git merge --ff-only live`. If ff fails → exit 1 with branched message pointing at `/gitlore:resolve` (placeholder for Plan 03).
- If memory worktree is dirty → emit `systemWarning` (just stderr in Plan 01), skip ff.

- [ ] **Step 1: Append failing tests.**

```bash
@test "rejects parent branch named 'live'" {
  make_parent_with_memory
  git checkout -q -b live
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"reserved"* ]] || [[ "${output}${stderr}" == *"live"* ]]
}

@test "creates worktree branch matching parent branch name from live" {
  make_parent_with_memory
  git checkout -q -b feat-x
  (cd memory && git checkout -q live)  # leave memory on live so SessionStart needs to act
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  run git -C memory branch --list feat-x
  [[ "$output" == *feat-x* ]]
}

@test "ff-merges memory branch to live when clean" {
  make_parent_with_memory
  # Advance live ahead of worktree branch.
  (
    cd memory
    git checkout -q live
    echo extra > MEMORY.md
    git commit -aq -m "Advance live"
    git checkout -q worktree
  )
  git checkout -q -b worktree  # parent branch mirrors memory's worktree branch
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  bash "$SESSION_START"
  # After SessionStart, memory worktree branch should equal live tip.
  livesha=$(git -C memory rev-parse live)
  wtsha=$(git -C memory rev-parse worktree)
  [ "$livesha" = "$wtsha" ]
}

@test "warns and skips ff when memory is dirty" {
  make_parent_with_memory
  echo dirty > memory/scratch.md
  git checkout -q -b worktree
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"uncommitted"* ]] || [[ "${output}${stderr}" == *"dirty"* ]]
}
```

- [ ] **Step 2: Run; confirm 4 failures.**

- [ ] **Step 3: Extend the SessionStart script.**

Append to `scripts/cc-hooks/session-start.sh` after the wrapper emission:

```bash
# Branch model.
parent_branch=$(gitlore_parent_branch)
if [ "$parent_branch" = "live" ]; then
  msg=$(gitlore_say_for_agent_or_user \
    "gitlore: parent branch 'live' collides with the memory trunk. Rename the parent branch (git branch -m) before continuing." \
    "gitlore: this repo's parent branch is named 'live', which collides with gitlore's memory trunk. Rename it (git branch -m) before using gitlore.")
  echo "$msg" >&2
  exit 1
fi

# Init the submodule worktree if needed.
if [ ! -f "$mempath/.git" ] && [ ! -d "$mempath/.git" ]; then
  git submodule update --init -- "$mempath" >&2
fi

# Determine the target memory branch.
if [ "$parent_branch" = "DETACHED" ]; then
  # Detached: ensure memory is detached at live's tip.
  git -C "$mempath" checkout --detach live >/dev/null 2>&1 || true
else
  if git -C "$mempath" show-ref --verify --quiet "refs/heads/$parent_branch"; then
    git -C "$mempath" checkout -q "$parent_branch"
  else
    git -C "$mempath" checkout -q -b "$parent_branch" live
  fi
fi

# ff merge if memory is clean.
if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  if ! git -C "$mempath" merge --ff-only live >/dev/null 2>&1; then
    msg=$(gitlore_say_for_agent_or_user \
      "gitlore: memory branch '$parent_branch' diverged from live. Run /gitlore:resolve, then /clear." \
      "gitlore: memory branch '$parent_branch' has diverged from live. Open this project in Claude Code and run /gitlore:resolve, then start a fresh session.")
    echo "$msg" >&2
    exit 1
  fi
else
  msg=$(gitlore_say_for_agent_or_user \
    "gitlore: memory has uncommitted changes; skipping live ff-merge." \
    "gitlore: memory has uncommitted changes; skipping live ff-merge.")
  echo "$msg" >&2
fi
```

- [ ] **Step 4: Verify.**

Run: `bats tests/cc_hook_session_start.bats`
Expected: 7 passing (3 from Task 10 + 4 new).

- [ ] **Step 5: Commit.**

```bash
git add scripts/cc-hooks/session-start.sh tests/cc_hook_session_start.bats
git commit -m "✨ feat: SessionStart enforces branch model and ff-merges to live"
```

---

## Task 12: SessionStart — sentinel replay

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh`
- Modify: `tests/cc_hook_session_start.bats`

Behavior: after wrappers are emitted, read `.claude/gitlore-hook-setup`:
- Empty/missing → warn (one-time) and continue.
- `direct` → run `scripts/hook-manager/wire-direct.sh`.
- `manual` → emit `systemWarning` reminding the user to wire manually.
- Anything else → execute as a shell command in repo root (e.g. `lefthook install`).

- [ ] **Step 1: Append failing tests.**

```bash
@test "sentinel 'direct' re-applies direct wiring" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'direct\n' > .claude/gitlore-hook-setup
  bash "$SESSION_START"
  grep -q '# gitlore: managed' .git/hooks/pre-commit
}

@test "sentinel 'manual' emits a reminder to stderr" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'manual\n' > .claude/gitlore-hook-setup
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"manual"* ]]
}

@test "arbitrary sentinel is executed as a shell command" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'touch SENTINEL_RAN\n' > .claude/gitlore-hook-setup
  bash "$SESSION_START"
  [ -f SENTINEL_RAN ]
}
```

- [ ] **Step 2: Run; confirm 3 failures.**

- [ ] **Step 3: Append sentinel handling to SessionStart.**

```bash
SENTINEL=".claude/gitlore-hook-setup"
if [ -f "$SENTINEL" ]; then
  cmd=$(head -1 "$SENTINEL" | tr -d '\n')
  case "$cmd" in
    "")
      echo "gitlore: empty sentinel; nothing to replay" >&2
      ;;
    direct)
      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
      ;;
    manual)
      echo "gitlore: hook wiring is 'manual'; verify .git/gitlore-pre-* are still invoked by your hooks." >&2
      ;;
    *)
      sh -c "$cmd"
      ;;
  esac
fi
```

- [ ] **Step 4: Verify.**

Run: `bats tests/cc_hook_session_start.bats`
Expected: 10 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/cc-hooks/session-start.sh tests/cc_hook_session_start.bats
git commit -m "✨ feat: SessionStart replays hook-setup sentinel"
```

---

## Task 13: `/gitlore:install` skill content + orchestration

**Files:**
- Modify: `commands/gitlore/install.md` (replace stub)
- Modify: `skills/install/SKILL.md` (replace stub)
- Create: `scripts/install/run.sh`
- Create: `scripts/install/init-submodule.sh`
- Create: `scripts/install/write-settings.sh`
- Create: `tests/install_run.bats`

Scope for Plan 01: **local-only install.** No remote creation, no D8 confirmation, no install-time disclosure. Those land in Plan 02.

Install flow (local-only):
1. Verify in a parent git repo.
2. Prompt (via the command's frontmatter / agent) for memory path (default `memory`) and `precommitCommand`.
3. If memory path exists with content, refuse.
4. Run `init-submodule.sh "$path" "$precommit_cmd"`:
   - `git submodule add ./<local-bare-or-empty>.git <path>` (no remote yet — register submodule with a local placeholder URL that can be re-pointed in Plan 02).
   - Seed: copy auto-memory from `~/.claude/projects/<hash>/memory` if present, else write `MEMORY.md` scaffold.
   - `git -C <path> add -A && git -C <path> commit -m "Initial memory"`.
   - Create `live` at HEAD; create worktree branch (from parent branch name or detached HEAD).
5. Run `write-settings.sh`:
   - `.claude/settings.json` ← `gitlore.enabled: true` and `gitlore.precommitCommand: <cmd>`.
   - `.claude/settings.local.json` ← `autoMemoryDirectory: <abs>`.
   - `git config gitlore.hooksDir "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks"`.
6. Run `scripts/emit-wrappers.sh`.
7. Run `scripts/hook-manager/detect.sh` and dispatch to the matching wiring.
8. Leave staged tracked changes (`.gitmodules`, the memory submodule pointer, `.claude/settings.json`, `.claude/gitlore-hook-setup`) for the user to commit.

Idempotency:
- Existing submodule registered → skip submodule add; verify branches.
- Existing `gitlore.enabled: true` → still rewrite (harmless).
- Existing sentinel + wiring marker → re-run wiring; it's a no-op via marker.

- [ ] **Step 1: Write the command file.**

`commands/gitlore/install.md`:

```markdown
---
description: Install gitlore in this repository
argument-hint: "[memory-path] [precommit-command]"
allowed-tools: ["Bash"]
---

# /gitlore:install

You are installing gitlore in the user's current repository.

## Steps

1. **Confirm context.** Verify you are at the root of a git working tree. Run:
   ```
   git rev-parse --show-toplevel
   ```
   If this fails, tell the user to cd into a git repo and abort.

2. **Gather inputs.** If `$1` was supplied, use it as the memory path; otherwise ask the user, defaulting to `memory`. If `$2` was supplied, use it as the precommit command; otherwise ask the user (e.g. `lefthook run pre-commit`, `pre-commit run --all-files`, etc.).

3. **Run the install orchestrator.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"
   ```

   The script exits 0 on success or a partial-but-recoverable install, non-zero on a hard error. On non-zero, surface stderr verbatim and stop.

4. **Summarize.** Tell the user:
   - the memory submodule path,
   - that hooks are wired (which manager),
   - and that they should commit the staged changes (`.gitmodules`, memory pointer, `.claude/settings.json`, `.claude/gitlore-hook-setup`) when they're ready.

Note: this is the local-only flow. Remote setup is a separate command (added in a later plan).
```

- [ ] **Step 2: Write the skill file.**

`skills/install/SKILL.md`:

```markdown
---
name: gitlore-install
description: Install gitlore memory submodule and wire git hooks (local-only)
---

This skill orchestrates the gitlore local install. See `commands/gitlore/install.md`
for the agent-facing flow. Internals: `scripts/install/run.sh`.

Key invariants:
- Memory submodule is registered as `gitlore-memory` regardless of working-tree path.
- Trunk branch is `live`. Worktree branch is named after the parent branch (or detached HEAD).
- Settings under `.claude/settings.json` are tracked; `.claude/settings.local.json` is gitignored.
- Hook wrappers live at `.git/gitlore-pre-{commit,push}` and are regenerated each SessionStart.
```

- [ ] **Step 3: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "install creates gitlore-memory submodule at requested path" {
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
  [ -d memory ]
  run git config --file .gitmodules submodule.gitlore-memory.path
  [ "$output" = "memory" ]
}

@test "install creates live and worktree branches inside memory" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run git -C memory branch --list live
  [[ "$output" == *live* ]]
  run git -C memory branch --list main  # parent branch is main from setup
  [[ "$output" == *main* ]]
}

@test "install writes settings.json keys" {
  bash "$RUN_INSTALL" memory "lefthook run pre-commit"
  [ "$(jq -r '.gitlore.enabled' .claude/settings.json)" = "true" ]
  [ "$(jq -r '.gitlore.precommitCommand' .claude/settings.json)" = "lefthook run pre-commit" ]
}

@test "install writes wrappers and sentinel" {
  bash "$RUN_INSTALL" memory "echo precommit"
  [ -x .git/gitlore-pre-commit ]
  [ -f .claude/gitlore-hook-setup ]
}

@test "install refuses when memory path exists with content" {
  mkdir memory && touch memory/unrelated.txt
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
}

@test "install is idempotent" {
  bash "$RUN_INSTALL" memory "echo precommit"
  run bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 4: Run; confirm 6 failures.**

- [ ] **Step 5: Implement `scripts/install/run.sh`.**

```bash
#!/usr/bin/env bash
set -euo pipefail

mempath="${1:-memory}"
precommit_cmd="${2:-}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# Must be at repo root.
toplevel=$(git rev-parse --show-toplevel)
[ "$PWD" = "$toplevel" ] || { echo "Run /gitlore:install from the repo root ($toplevel)." >&2; exit 1; }

# Refuse non-empty existing path that isn't already our submodule.
if [ -e "$mempath" ] && ! git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  if [ -n "$(ls -A "$mempath" 2>/dev/null || true)" ]; then
    echo "gitlore: '$mempath' exists and is not empty. Choose another path." >&2
    exit 2
  fi
fi

bash "$PLUGIN_ROOT/scripts/install/init-submodule.sh" "$mempath"
bash "$PLUGIN_ROOT/scripts/install/write-settings.sh" "$mempath" "$precommit_cmd"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"

manager=$(bash "$PLUGIN_ROOT/scripts/hook-manager/detect.sh")
case "$manager" in
  lefthook)   bash "$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"   ;;
  husky)      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"      ;;
  overcommit) bash "$PLUGIN_ROOT/scripts/hook-manager/wire-overcommit.sh" ;;
  direct)     bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"     ;;
  manual|multi:*) bash "$PLUGIN_ROOT/scripts/hook-manager/wire-manual.sh" ;;
esac

echo "gitlore: install complete." >&2
echo "Review the staged changes (.gitmodules, $mempath/, .claude/settings.json, .claude/gitlore-hook-setup) and commit when ready." >&2
```

- [ ] **Step 6: Implement `scripts/install/init-submodule.sh`.**

Strategy: avoid `git submodule add` (which requires a cloneable URL with a HEAD). Instead, init a plain repo at `<mempath>`, seed and commit, then use `git submodule absorbgitdirs` to relocate its `.git/` into the parent's `.git/modules/gitlore-memory`. Write `.gitmodules` by hand with a placeholder URL; Plan 02 rewrites it to point at a real remote.

```bash
#!/usr/bin/env bash
set -euo pipefail

mempath="$1"
parent_root=$(git rev-parse --show-toplevel)

# Idempotency: if already registered, just ensure branches exist and exit.
already_registered=0
if git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  already_registered=1
fi

if [ "$already_registered" -eq 0 ]; then
  # 1. Plain init at the target path.
  git init -q "$mempath"
  (
    cd "$mempath"
    git config user.email "gitlore@local"
    git config user.name  "gitlore"
  )

  # 2. Seed content (auto-memory migration, else scaffold).
  hash=$(printf '%s' "$parent_root" | shasum | cut -d' ' -f1)
  src="$HOME/.claude/projects/$hash/memory"
  if [ -d "$src" ]; then
    cp -R "$src"/. "$mempath/"
  else
    cat > "$mempath/MEMORY.md" <<'EOF'
# Memory Index

(populated by Claude over time)
EOF
  fi

  # 3. Initial commit.
  (
    cd "$mempath"
    git add -A
    git commit -q -m "Initial memory"
  )

  # 4. Register in .gitmodules with a local placeholder URL.
  #    Plan 02 rewrites this to a real remote.
  placeholder_url="./.git/gitlore-placeholder"
  if [ -f .gitmodules ] && grep -q '\[submodule "gitlore-memory"\]' .gitmodules; then
    :
  else
    {
      printf '[submodule "gitlore-memory"]\n'
      printf '\tpath = %s\n' "$mempath"
      printf '\turl = %s\n' "$placeholder_url"
    } >> .gitmodules
  fi

  # 5. Absorb gitdirs: moves <mempath>/.git into .git/modules/gitlore-memory
  #    and converts <mempath>/.git into a pointer file. This is what
  #    `git submodule add` would have done, but we drove the init manually.
  git submodule absorbgitdirs "$mempath"

  # 6. Stage parent-side artifacts.
  git add .gitmodules "$mempath"
fi

# 7. live + worktree branches (idempotent).
cd "$mempath"
git show-ref --verify --quiet refs/heads/live || git branch live

cd "$parent_root"
parent_branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo DETACHED)

cd "$mempath"
if [ "$parent_branch" = "DETACHED" ]; then
  git checkout -q --detach live
else
  git show-ref --verify --quiet "refs/heads/$parent_branch" || git branch "$parent_branch" live
  git checkout -q "$parent_branch"
fi
```

> Notes:
>
> - `git submodule absorbgitdirs` requires Git ≥ 2.13. Document in the readme.
> - The placeholder URL means `git submodule update --init` will fail in a fresh clone until Plan 02 wires a real URL. That's expected; clone scenarios are exercised in Plan 05.
> - The auto-memory hash derivation here is a placeholder — Claude Code uses a specific hashing scheme for its project memory paths. Verify before relying on auto-migration. If wrong, the install still works; it just skips migration and writes the scaffold instead.

- [ ] **Step 7: Implement `scripts/install/write-settings.sh`.**

```bash
#!/usr/bin/env bash
set -euo pipefail

mempath="$1"
precommit_cmd="$2"

mkdir -p .claude

# settings.json — tracked.
if [ -f .claude/settings.json ]; then
  tmp=$(mktemp)
  jq --arg pc "$precommit_cmd" \
     '.gitlore.enabled = true | .gitlore.precommitCommand = $pc' \
     .claude/settings.json > "$tmp"
  mv "$tmp" .claude/settings.json
else
  jq -n --arg pc "$precommit_cmd" \
     '{gitlore: {enabled: true, precommitCommand: $pc}}' > .claude/settings.json
fi

# settings.local.json — untracked.
absmem=$(cd "$mempath" && pwd)
if [ -f .claude/settings.local.json ]; then
  tmp=$(mktemp)
  jq --arg p "$absmem" '.autoMemoryDirectory = $p' .claude/settings.local.json > "$tmp"
  mv "$tmp" .claude/settings.local.json
else
  jq -n --arg p "$absmem" '{autoMemoryDirectory: $p}' > .claude/settings.local.json
fi

# Make sure .claude/settings.local.json is gitignored.
if [ -f .gitignore ]; then
  grep -qx '.claude/settings.local.json' .gitignore || \
    printf '\n.claude/settings.local.json\n' >> .gitignore
else
  printf '.claude/settings.local.json\n' > .gitignore
fi

# Hook dir.
git config gitlore.hooksDir "${CLAUDE_PLUGIN_ROOT}/scripts/git-hooks"
```

- [ ] **Step 8: Verify.**

Run: `bats tests/install_run.bats`
Expected: 6 passing.

- [ ] **Step 9: Commit.**

```bash
git add commands/gitlore/install.md skills/install/SKILL.md scripts/install/run.sh scripts/install/init-submodule.sh scripts/install/write-settings.sh tests/install_run.bats
git commit -m "✨ feat: /gitlore:install local-only orchestration"
```

---

## Task 14: PostToolUse hook — commit-message preparation trigger

**Files:**
- Create: `scripts/cc-hooks/post-tool-use.sh`
- Create: `tests/cc_hook_post_tool_use.bats`

Input: CC PostToolUse hooks receive JSON on stdin including `tool_name`, `tool_input.command`, `tool_response.exit_code`. We only act on `Bash` tools (already matcher-gated in `hooks.json`) and a command prefix match against `gitlore.precommitCommand`.

Trigger conditions (ALL):
1. `tool_response.exit_code == 0`.
2. The bash command prefix-matches the configured `gitlore.precommitCommand`.
3. `gitlore-memory` submodule is registered.
4. Memory submodule worktree is dirty.
5. Commit message file is absent or stale.

Output: emit `additionalContext` JSON instructing Claude to summarize, confirm with the user, then write the commit message file.

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

POST="$PLUGIN_ROOT/scripts/cc-hooks/post-tool-use.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  mkdir -p .claude
  jq -n --arg pc "lefthook run pre-commit" \
     '{gitlore: {enabled:true, precommitCommand:$pc}}' > .claude/settings.json
}
teardown() { teardown_tmp_repo; }

stdin() { printf '%s' "$1" | bash "$POST"; }

@test "no-op when tool_name is not Bash" {
  payload='{"tool_name":"Read","tool_input":{},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when command does not match precommit prefix" {
  payload='{"tool_name":"Bash","tool_input":{"command":"echo unrelated"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}

@test "no-op when memory is clean" {
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}

@test "emits additionalContext when memory is dirty and matched" {
  echo dirty > memory/notes.md
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *additionalContext* ]]
  [[ "$output" == *"Summarize pending memory changes"* ]]
}

@test "no-op when commit-msg file is fresh" {
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'pre-approved\n' > "$msgfile"
  # touch msg file after the memory edit so it's fresh
  touch "$msgfile"
  payload='{"tool_name":"Bash","tool_input":{"command":"lefthook run pre-commit"},"tool_response":{"exit_code":0}}'
  run stdin "$payload"
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run; confirm 5 failures.**

- [ ] **Step 3: Implement.**

`scripts/cc-hooks/post-tool-use.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
[ "$tool" = "Bash" ] || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
[ -n "$cmd" ] || exit 0

exit_code=$(jq -r '.tool_response.exit_code // 0' <<<"$payload")
[ "$exit_code" = "0" ] || exit 0

# Configured prefix.
prefix=$(jq -r '.gitlore.precommitCommand // empty' .claude/settings.json 2>/dev/null)
[ -n "$prefix" ] || exit 0
case "$cmd" in "$prefix"*) ;; *) exit 0 ;; esac

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

[ "$(gitlore_memory_dirty "$mempath")" = "1" ] || exit 0
[ "$(gitlore_commit_msg_freshness "$mempath")" != "yes" ] || exit 0

msgfile=$(gitlore_commit_msg_file "$mempath")

cat <<EOF
{
  "additionalContext": "gitlore: memory ($mempath) has uncommitted changes. Summarize the pending memory changes in prose, present the summary to the user, await explicit confirmation, then write the approved summary to $msgfile. On rejection, discuss and retry."
}
EOF
```

- [ ] **Step 4: Verify.**

Run: `bats tests/cc_hook_post_tool_use.bats`
Expected: 5 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/cc-hooks/post-tool-use.sh tests/cc_hook_post_tool_use.bats
git commit -m "✨ feat: PostToolUse triggers memory commit-msg preparation"
```

---

## Task 15: pre-commit git hook — happy path (commit + ff push)

**Files:**
- Modify: `scripts/git-hooks/pre-commit` (replace the placeholder from Task 10)
- Create: `tests/git_hook_pre_commit.bats`

Logic (matches design §pre-commit):
1. Fail-silent no-op if `gitlore-memory` not registered → `exit 0`.
2. Resolve `mempath`, target branch (from memory HEAD).
3. If memory clean **and** memory HEAD == `live` → `exit 0`.
4. If memory dirty **and** commit-msg absent or stale → `exit 1` with branched message (Claude-targeted vs user-targeted).
5. If memory dirty **and** commit-msg fresh → commit using `-F`, delete msg file.
6. If branch ahead of `live` → `git push . <branch>:live` (ff). On failure → `exit 1` with branched message pointing at `/gitlore:resolve` (placeholder for Plan 03).

- [ ] **Step 1: Write failing tests.**

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

HOOK="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "exits 0 when gitlore is not configured" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory clean and at live" {
  make_parent_with_memory
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 1 with hint when memory dirty and no approved summary" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"approved commit summary"* ]] || \
    [[ "${output}${stderr}" == *"Prepare a summary"* ]]
}

@test "commits and ff-pushes to live when summary is fresh" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  # memory worktree HEAD advanced and live ff-ed.
  wt=$(git -C memory rev-parse worktree)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  # msg file deleted.
  [ ! -f "$msgfile" ]
}

@test "exits 1 with /gitlore:resolve hint when branch diverged from live" {
  make_parent_with_memory
  # Diverge: advance live without ff to worktree branch.
  (
    cd memory
    git checkout -q live
    echo "live-only" > MEMORY.md
    git commit -aq -m "Diverging commit on live"
    git checkout -q worktree
  )
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  CLAUDECODE=1 run bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]]
}
```

- [ ] **Step 2: Run; confirm 5 failures (the placeholder always returns 0).**

- [ ] **Step 3: Implement.**

`scripts/git-hooks/pre-commit`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.path" >/dev/null 2>&1 || exit 0

mempath=$(gitlore_memory_path)
branch=$(git -C "$mempath" symbolic-ref --short -q HEAD 2>/dev/null || echo DETACHED)
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
  head_sha=$(git -C "$mempath" rev-parse HEAD)
fi

# ff-push branch → live.
if [ "$branch" != "DETACHED" ] && [ -n "$live_sha" ]; then
  if ! git -C "$mempath" push -q . "$branch:live" 2>/dev/null; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory branch diverged from live. Run /gitlore:resolve to merge, then retry the commit." \
      "gitlore: memory branch diverged from live. Open this project in Claude Code and run /gitlore:resolve, then retry." >&2
    exit 1
  fi
fi

exit 0
```

- [ ] **Step 4: Verify.**

Run: `bats tests/git_hook_pre_commit.bats`
Expected: 5 passing.

- [ ] **Step 5: Commit.**

```bash
git add scripts/git-hooks/pre-commit tests/git_hook_pre_commit.bats
git commit -m "✨ feat: pre-commit hook commits memory and ff-pushes to live"
```

---

## Task 16: Integration — happy path commit

**Files:**
- Create: `tests/integration_happy_path.bats`

Sim­ulates the full local happy path end-to-end. Doesn't invoke real Claude — it manually performs the steps Claude would, exercising the scripts in sequence.

- [ ] **Step 1: Write the integration test.**

```bash
#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
}
teardown() { teardown_tmp_repo; }

@test "install + edit memory + commit-msg + parent commit → memory committed and ff-pushed" {
  # 1. Install.
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "echo precommit"

  # 2. SessionStart fires (simulated).
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

  # 3. Claude edits memory.
  echo "added during session" >> memory/MEMORY.md

  # 4. Claude runs the configured pre-commit command (echo precommit). PostToolUse fires.
  payload='{"tool_name":"Bash","tool_input":{"command":"echo precommit"},"tool_response":{"exit_code":0}}'
  out=$(printf '%s' "$payload" | bash "$PLUGIN_ROOT/scripts/cc-hooks/post-tool-use.sh")
  [[ "$out" == *additionalContext* ]]

  # 5. Claude writes the commit-msg file (simulating user approval).
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: record session edits\n' > "$msgfile"

  # 6. Parent's pre-commit hook fires (driven by the wrapper).
  bash .git/gitlore-pre-commit

  # Assertions.
  [ ! -f "$msgfile" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  run git -C memory log --oneline
  [[ "$output" == *"record session edits"* ]]
}
```

- [ ] **Step 2: Run.**

Run: `bats tests/integration_happy_path.bats`
Expected: 1 passing.

- [ ] **Step 3: Commit.**

```bash
git add tests/integration_happy_path.bats
git commit -m "🧪 add end-to-end happy-path integration test"
```

---

## Task 17: README + dev convenience

**Files:**
- Modify: `docs/plugin-readme.md`
- Create: `Makefile`

- [ ] **Step 1: Expand `docs/plugin-readme.md`.**

```markdown
# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the design and `docs/plans/` for implementation plans.

## Install (local only, Plan 01)

In your project repo, with Claude Code running:

    /gitlore:install

You'll be asked for a memory subpath (default `memory`) and your project's
pre-commit command (e.g. `lefthook run pre-commit`).

## Development

    make test       # runs the bats suite

Dependencies: `bash` ≥ 3.2, `git`, `jq`, `bats-core` ≥ 1.10. Optional: `yq` for
hook-manager YAML edits.

## Status

- Plan 01 — local memory pipeline (this scope) — IN PROGRESS.
- Plans 02–05 — remote, resolve, worktrees, polish — TODO.
```

- [ ] **Step 2: Add a `Makefile`.**

```makefile
.PHONY: test test-unit test-integration

test: test-unit test-integration

test-unit:
	bats tests/lib_util.bats tests/lib_log.bats tests/hook_manager_detect.bats tests/hook_manager_wire.bats tests/emit_wrappers.bats tests/cc_hook_session_start.bats tests/cc_hook_post_tool_use.bats tests/git_hook_pre_commit.bats tests/install_run.bats tests/smoke.bats

test-integration:
	bats tests/integration_happy_path.bats
```

- [ ] **Step 3: Run the full suite.**

Run: `make test`
Expected: all tests pass.

- [ ] **Step 4: Commit.**

```bash
git add docs/plugin-readme.md Makefile
git commit -m "📝 docs: expand readme and add Makefile"
```

---

## Done criteria for Plan 01

- [ ] All bats tests pass: `make test`.
- [ ] In a scratch repo: `/gitlore:install` succeeds, scaffolds `memory/`, writes `.claude/settings.json` + `.claude/gitlore-hook-setup`, wires the user's hook manager, and creates `live` + parent-branch-name branch inside the memory submodule.
- [ ] After `git commit` in the parent repo with dirty memory and a fresh commit-msg file, memory advances and `live` fast-forwards to the new commit.
- [ ] After `git commit` with dirty memory but no fresh msg file, the pre-commit hook fails loudly with the Claude-targeted message (when `$CLAUDECODE` set) or the user-targeted message (when unset).
- [ ] Restarting Claude Code in the same repo re-emits wrappers, re-applies sentinel wiring, and the system continues to work.
- [ ] In a repo without a `gitlore-memory` submodule, all hooks no-op silently (FR 12: coexistence).

---

## Known caveats and verifications deferred to execution

These are spots where the design or external tools may force changes during implementation; flag them in PRs rather than guessing:

1. **CC plugin manifest schema.** `plugin.json` field names and the `hooks.json` shape must match the current CC version. Verify with `plugin-dev:plugin-structure` and `plugin-dev:hook-development` skills at execution time.
2. **CC hook input JSON shape** for `SessionStart` and `PostToolUse`. The tests above mock minimal payloads; verify the keys the scripts read against current CC documentation.
3. **`stat`/`find` portability** in `gitlore_commit_msg_freshness`. The current implementation tries BSD first, GNU second; if tests fail on either OS, normalize via a small `gitlore_mtime` helper.
4. **Lefthook / Overcommit duplicate top-level keys.** The naive append wiring may break on a strict YAML parser. Switch to `yq` if so (already noted in Tasks 6 and 8).
5. **Auto-memory path hash** used by `init-submodule.sh` to migrate existing `~/.claude/projects/<hash>/memory/` content. The placeholder uses `shasum` of the repo abs path; the real CC scheme may differ. If wrong, install simply skips migration — non-fatal.
6. **`gitlore.hooksDir` resolution** in `pre-commit` when CC is not running. The hook reads `git config gitlore.hooksDir`; if unset the wrapper short-circuits before this script runs. Confirm by manually unsetting the config in a scratch repo.
