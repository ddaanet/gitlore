# Gitlink-Aware Hook Wrappers + Worktree Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every gitlore hook wrapper path gitlink-aware so commits and SessionStart work in linked git worktrees, and absorb Plan 06's two deliverables (lazy memory-worktree creation at SessionStart, advisory `WorktreeRemove` cleanup).

**Architecture:** gitlore writes two flat wrapper scripts (`gitlore-pre-commit`, `gitlore-pre-push`) and wires the repo's hook manager to `exec` them. The wrappers were anchored at the literal relative path `.git/gitlore-<hook>`, which only resolves when `.git` is a directory — i.e. only in the main worktree. In a *linked* worktree `.git` is a gitlink **file**, so the write aborts SessionStart under `set -e` and the shared wired hook `exec`s a non-existent path and blocks the commit (verified empirically, git 2.47.3). The fix (design decision **D11**): anchor every wrapper at `$(git rev-parse --git-common-dir)/gitlore-<hook>` — the common dir is shared across all worktrees, so one emission is reachable and executable from every worktree, including a session-less one. The direct-wiring hook **file** likewise moves from literal `.git/hooks/<hook>` to `git rev-parse --git-path hooks/<hook>` (the shared common-dir hooks file). Both git hooks get an early `[ -e "$mempath/.git" ] || exit 0` guard so a session-less worktree (no memory submodule worktree yet) never blocks. Finally `SessionStart` lazily creates the memory submodule worktree when missing (already drafted in the working tree), and a new advisory `WorktreeRemove` hook tears it down.

**Tech Stack:** POSIX sh / bash scripts, `git` plumbing (`rev-parse --git-common-dir`, `--git-path`, `worktree add/remove/prune`), `jq`, bats tests, PyYAML/`yq` for YAML hook-manager configs.

---

## Background: verified facts this plan relies on

These were confirmed empirically (git 2.47.3) during planning — an implementer does **not** need to re-verify them, but should understand them:

- **`git rev-parse --git-common-dir`** → `.git` (relative) in the main worktree; the shared absolute `<main>/.git` in a linked worktree. **Shared across worktrees** — this is the correct wrapper anchor.
- **`git rev-parse --git-path hooks/pre-commit`** → `.git/hooks/pre-commit` in main; the shared `<main>/.git/hooks/pre-commit` in a linked worktree. Hooks live in the common dir, so this is shared too — the correct anchor for the direct hook file.
- **`git rev-parse --git-path gitlore-pre-commit`** → `.git/gitlore-pre-commit` in main; the **per-worktree** `<main>/.git/worktrees/<name>/gitlore-pre-commit` in a linked worktree. This is the **rejected** anchor (D11 rejected alternative) — a session-less worktree's shared stub would `exec` a per-worktree wrapper that does not exist. Do **not** use `--git-path` for the wrapper.
- **The current bug:** in a linked worktree, `scripts/emit-wrappers.sh` dies with `.git/gitlore-pre-commit: Not a directory` and aborts SessionStart **before** the memory-worktree-creation block runs. (Reproducible with the Task 2 test, which is already red in the working tree.)
- **Overcommit `command:` array semantics:** overcommit exec's the array directly (no shell) and appends the staged files as extra argv. The form `['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"','gitlore']` sets `$0=gitlore` and the appended files become `$@`; `exec "<wrapper>" "$@"` forwards them, spaces intact. Verified: `sh -c 'exec "$0" "$@"' wrapper a.rb "b c.rb"` delivers two args.

## Working-tree state at plan start

Two files already carry **uncommitted** edits from an aborted earlier attempt; this plan folds them in rather than rewriting:

- `scripts/cc-hooks/session-start.sh` — the memory-worktree-creation block (lines ~70-85) is already added and matches the D11/Plan-06 design. **Do not rewrite it.** Task 2 verifies and commits it.
- `tests/cc_hook_session_start.bats` — the linked-worktree test ("creates the memory worktree in a linked (CC-created) worktree…") is already added and is currently **red** because `emit-wrappers` aborts first. Task 1 turns it green.

## Test runner

`bats` is not on `PATH` in this environment. Prefix test commands with:

```bash
export PATH="/tmp/claude-1000/bats-core/bin:$PATH"
```

Run a single file: `bats tests/<file>.bats`. Run the whole suite: `make test` (after adding the new file to the Makefile in Task 9). Ignore `BW02` minimum-version warnings — they are pre-existing and harmless.

## File map

| File | Change |
|------|--------|
| `scripts/emit-wrappers.sh` | Anchor wrapper output at `--git-common-dir` (write side). |
| `scripts/cc-hooks/session-start.sh` | Already edited (memory-worktree creation); verify + commit. |
| `scripts/hook-manager/wire-direct.sh` | Hook file via `--git-path hooks/<hook>`; stub `exec`s common-dir wrapper. |
| `scripts/hook-manager/wire-husky.sh` | Appended `exec` uses common-dir wrapper. |
| `scripts/hook-manager/wire-lefthook.sh` | `run:` value uses common-dir wrapper (yq + python paths). |
| `scripts/hook-manager/wire-overcommit.sh` | `command:` array uses `sh -c` + common-dir wrapper (yq + python paths). |
| `scripts/hook-manager/wire-manual.sh` | Printed instructions reference the common-dir wrapper. |
| `scripts/git-hooks/pre-commit` | Early `[ -e "$mempath/.git" ]` session-less guard. |
| `scripts/git-hooks/pre-push` | Early `[ -e "$mempath/.git" ]` session-less guard. |
| `scripts/cc-hooks/worktree-remove.sh` | **New** advisory `WorktreeRemove` hook. |
| `hooks/hooks.json` | Register `WorktreeRemove`. |
| `tests/emit_wrappers.bats` | Add linked-worktree write test. |
| `tests/hook_manager_wire.bats` | Update path assertions; add direct linked-worktree + overcommit verification tests. |
| `tests/git_hook_pre_commit.bats` | Add session-less-worktree guard test. |
| `tests/pre_push_hook.bats` | Add session-less-worktree guard test. |
| `tests/cc_hook_worktree_remove.bats` | **New** test file. |
| `Makefile` | Add `tests/cc_hook_worktree_remove.bats` to `test-unit`. |

---

### Task 1: Anchor the wrapper writer at the git common dir

**Files:**
- Modify: `scripts/emit-wrappers.sh`
- Test: `tests/emit_wrappers.bats`

- [ ] **Step 1: Add the failing linked-worktree test**

Append to `tests/emit_wrappers.bats` (the file already defines `EMIT` and the tmp-repo setup/teardown):

```bash
@test "emit-wrappers in a linked worktree writes to the shared common dir, not the gitlink file" {
  echo seed > f && git add f && git commit -q -m seed
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  ( cd "$WT" && bash "$EMIT" )
  # The wrapper must land in the shared common dir (= the main worktree's .git),
  # NOT next to the gitlink file (which would fail to write).
  [ -x "$TMP_REPO/.git/gitlore-pre-commit" ]
  [ -x "$TMP_REPO/.git/gitlore-pre-push" ]
  rm -rf "$WT"
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/emit_wrappers.bats`
Expected: the new test FAILS — `emit-wrappers` aborts with `.git/gitlore-pre-commit: Not a directory` inside the linked worktree.

- [ ] **Step 3: Anchor the writer at the common dir**

Replace the entire body of `scripts/emit-wrappers.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Anchor wrappers in the git COMMON dir (shared across all worktrees), not a
# literal `.git/` — in a linked worktree `.git` is a gitlink *file*, so a literal
# path fails to write. `git rev-parse --git-common-dir` resolves to `.git` in the
# main worktree and the shared `<main>/.git` in a linked one, so a single emission
# is reachable and executable from every worktree (D11).
common_dir=$(git rev-parse --git-common-dir)

write_wrapper() {
  local hook="$1"
  local out="$common_dir/gitlore-$hook"
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

(Only the anchor changed — the emitted wrapper body is identical. The wrapper itself still `exec`s `$HOOKS_DIR/<hook>` from the plugin's `gitlore.hooksDir`.)

- [ ] **Step 4: Run the emit-wrappers suite — all green**

Run: `bats tests/emit_wrappers.bats`
Expected: PASS, including the new test. The three pre-existing tests still pass because `--git-common-dir` is `.git` in the main (non-worktree) tmp repo, so they write `.git/gitlore-*` exactly as before.

- [ ] **Step 5: Commit**

```bash
git add scripts/emit-wrappers.sh tests/emit_wrappers.bats
git commit -m "fix: anchor hook wrappers at git common dir for linked worktrees"
```

---

### Task 2: Verify + commit the SessionStart memory-worktree creation (already drafted)

**Files:**
- Modify (already edited in working tree): `scripts/cc-hooks/session-start.sh`
- Test (already added in working tree): `tests/cc_hook_session_start.bats`

> The memory-worktree-creation block and its test are already present uncommitted. With Task 1 done, the previously-red test now passes. Do **not** rewrite either file; just confirm and commit. If the working-tree edits are somehow absent, re-create the block exactly as in Step 2.

- [ ] **Step 1: Run the session-start suite**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/cc_hook_session_start.bats`
Expected: PASS, including "creates the memory worktree in a linked (CC-created) worktree on the parent-named branch" — which was red before Task 1.

- [ ] **Step 2: Confirm the in-tree block matches the design**

`git diff scripts/cc-hooks/session-start.sh` must show this block replacing the old single-line `git submodule update --init` (it should already be present verbatim):

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

The subsequent checkout block (unchanged) then checks out `$parent_branch` from `live`, so a fresh linked worktree ends up on a memory branch named after its parent branch.

- [ ] **Step 3: Commit**

```bash
git add scripts/cc-hooks/session-start.sh tests/cc_hook_session_start.bats
git commit -m "feat: SessionStart creates the memory submodule worktree in linked worktrees"
```

---

### Task 3: Gitlink-aware direct hook wiring

**Files:**
- Modify: `scripts/hook-manager/wire-direct.sh`
- Test: `tests/hook_manager_wire.bats`

- [ ] **Step 1: Add `EMIT` to the wire test file**

Near the top of `tests/hook_manager_wire.bats`, after the existing `WIRE_*` definitions, add:

```bash
EMIT="$PLUGIN_ROOT/scripts/emit-wrappers.sh"
```

- [ ] **Step 2: Update the existing direct assertions + add a linked-worktree end-to-end test**

In `tests/hook_manager_wire.bats`, change the two existing direct tests' `exec .git/gitlore-...` assertions to the new common-dir form, then add a linked-worktree test.

In `@test "wire-direct installs .git/hooks/pre-commit and pre-push stubs"`, replace:

```bash
  grep -q 'exec .git/gitlore-pre-commit' .git/hooks/pre-commit
```
with:
```bash
  grep -qF 'git rev-parse --git-common-dir' .git/hooks/pre-commit
  grep -q 'gitlore-pre-commit' .git/hooks/pre-commit
```

In `@test "wire-direct is idempotent and preserves existing user hooks"`, replace both `grep -q 'exec .git/gitlore-pre-commit' .git/hooks/pre-commit` occurrences with:
```bash
  grep -q 'gitlore-pre-commit' .git/hooks/pre-commit
```

Then add this new test:

```bash
@test "wire-direct stub resolves the wrapper from a linked worktree (D11)" {
  echo seed > f && git add f && git commit -q -m seed
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  cd "$WT"
  bash "$EMIT"          # emit wrappers into the shared common dir
  bash "$WIRE_DIRECT"   # wire the stub via --git-path hooks/<hook>

  # A fake "real hook" the wrapper will exec, proving the whole chain resolves.
  fake="$WT/fakehooks" && mkdir -p "$fake"
  printf '#!/usr/bin/env sh\necho real-hook-ran\n' > "$fake/pre-commit"
  chmod +x "$fake/pre-commit"
  git config gitlore.hooksDir "$fake"

  hookfile=$(git rev-parse --git-path hooks/pre-commit)
  run "$hookfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real-hook-ran"* ]]
  rm -rf "$WT"
}
```

- [ ] **Step 3: Run to confirm the linked-worktree test fails**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/hook_manager_wire.bats`
Expected: the existing direct tests fail on the changed assertions (old script still writes `.git/gitlore-*`), and the new linked-worktree test fails (the stub `exec`s the literal `.git/gitlore-pre-commit`, which does not exist in the linked worktree).

- [ ] **Step 4: Rewrite `wire-direct.sh` to be gitlink-aware**

Replace the entire body of `scripts/hook-manager/wire-direct.sh` with:

```bash
#!/usr/bin/env bash
# wire-direct.sh — install pre-commit/pre-push stubs in the shared hooks dir.
#
# Gitlink-aware (D11): the hook FILE path resolves via `git rev-parse --git-path
# hooks/<hook>` (the shared common-dir hooks file — a literal `.git/hooks/...`
# breaks in a linked worktree), and the stub EXECs the wrapper via
# `$(git rev-parse --git-common-dir)/gitlore-<hook>` so it resolves from every
# worktree, including session-less ones.
#
# Exec semantics: the appended `exec ...` replaces the shell process, so any
# lines AFTER the gitlore block in an existing hook will not run.
set -euo pipefail

for hook in pre-commit pre-push; do
  f=$(git rev-parse --git-path "hooks/$hook")
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
    continue
  fi
  # Build the exec line: hook name expands now; `$(...)` and `$@` stay literal so
  # they expand when the hook runs.
  exec_line="exec \"\$(git rev-parse --git-common-dir)/gitlore-$hook\" \"\$@\""
  if [ -f "$f" ]; then
    { printf '\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } >> "$f"
  else
    { printf '#!/usr/bin/env sh\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } > "$f"
  fi
  chmod +x "$f"
done

mkdir -p .claude
printf 'direct\n' > .claude/gitlore-hook-setup
```

- [ ] **Step 5: Run the wire suite — direct tests green**

Run: `bats tests/hook_manager_wire.bats`
Expected: all direct tests PASS, including the linked-worktree end-to-end test. (Other managers' tests are still green — untouched.)

- [ ] **Step 6: Commit**

```bash
git add scripts/hook-manager/wire-direct.sh tests/hook_manager_wire.bats
git commit -m "fix: direct hook wiring resolves wrapper via git common dir (D11)"
```

---

### Task 4: Gitlink-aware husky wiring

**Files:**
- Modify: `scripts/hook-manager/wire-husky.sh`
- Test: `tests/hook_manager_wire.bats`

- [ ] **Step 1: Update the husky assertions**

In `@test "wire-husky appends guarded exec lines to .husky/pre-commit and pre-push"`, replace:

```bash
  grep -q 'exec .git/gitlore-pre-commit' .husky/pre-commit
  ...
  grep -q 'exec .git/gitlore-pre-push' .husky/pre-push
```
with:
```bash
  grep -qF 'git rev-parse --git-common-dir' .husky/pre-commit
  grep -q 'gitlore-pre-commit' .husky/pre-commit
  grep -qF 'git rev-parse --git-common-dir' .husky/pre-push
  grep -q 'gitlore-pre-push' .husky/pre-push
```

- [ ] **Step 2: Run to confirm failure**

Run: `bats tests/hook_manager_wire.bats`
Expected: the husky append test FAILS (old script writes `exec .git/gitlore-...`, no `--git-common-dir`).

- [ ] **Step 3: Update the husky exec line**

In `scripts/hook-manager/wire-husky.sh`, replace the append block:

```bash
  if ! grep -q '# gitlore: managed' "$f"; then
    cat >> "$f" <<EOF

# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  fi
```
with:
```bash
  if ! grep -q '# gitlore: managed' "$f"; then
    # Common-dir anchor (D11): resolves from every worktree, incl. linked ones.
    exec_line="exec \"\$(git rev-parse --git-common-dir)/gitlore-$hook\" \"\$@\""
    { printf '\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } >> "$f"
  fi
```

Also update the first-creation block so a freshly created husky file uses `printf` consistently (optional but tidy) — leave the `if [ ! -f "$f" ]` creation as-is; only the append changed.

- [ ] **Step 4: Run the wire suite — husky tests green**

Run: `bats tests/hook_manager_wire.bats`
Expected: all husky tests PASS (append, create-missing, idempotent, sentinel).

- [ ] **Step 5: Commit**

```bash
git add scripts/hook-manager/wire-husky.sh tests/hook_manager_wire.bats
git commit -m "fix: husky hook wiring resolves wrapper via git common dir (D11)"
```

---

### Task 5: Gitlink-aware lefthook wiring

**Files:**
- Modify: `scripts/hook-manager/wire-lefthook.sh`
- Test: `tests/hook_manager_wire.bats`

- [ ] **Step 1: Update the lefthook assertions**

In `@test "wire-lefthook adds gitlore command under pre-commit and pre-push"`, replace:

```bash
  grep -q '.git/gitlore-pre-commit' lefthook.yml
  grep -q '.git/gitlore-pre-push' lefthook.yml
```
with:
```bash
  grep -qF 'git rev-parse --git-common-dir' lefthook.yml
  grep -q 'gitlore-pre-commit' lefthook.yml
  grep -q 'gitlore-pre-push' lefthook.yml
```

In `@test "wire-lefthook preserves existing pre-commit commands"`, replace:
```bash
  grep -q '.git/gitlore-pre-commit' lefthook.yml
```
with:
```bash
  grep -q 'gitlore-pre-commit' lefthook.yml
```

- [ ] **Step 2: Run to confirm failure**

Run: `bats tests/hook_manager_wire.bats`
Expected: the lefthook add test FAILS (no `--git-common-dir` present yet). This environment has `python3`+PyYAML and no `yq`, so the python branch is what runs.

- [ ] **Step 3: Update both lefthook code paths**

In `scripts/hook-manager/wire-lefthook.sh`, in the **yq** branch replace:

```bash
  yq -i '.pre-commit.commands.gitlore.run = ".git/gitlore-pre-commit"' "$CONFIG"
  yq -i '.pre-push.commands.gitlore.run   = ".git/gitlore-pre-push"'   "$CONFIG"
```
with:
```bash
  yq -i '.pre-commit.commands.gitlore.run = "$(git rev-parse --git-common-dir)/gitlore-pre-commit"' "$CONFIG"
  yq -i '.pre-push.commands.gitlore.run   = "$(git rev-parse --git-common-dir)/gitlore-pre-push"'   "$CONFIG"
```

(The yq expression is single-quoted in shell, so `$(...)` reaches yq literally and is written as a literal string. Lefthook runs `run` through a shell, so the substitution expands at hook time.)

In the **python3** branch replace:
```python
for hook, wrapper in (
    ('pre-commit', '.git/gitlore-pre-commit'),
    ('pre-push',   '.git/gitlore-pre-push'),
):
```
with:
```python
for hook, wrapper in (
    ('pre-commit', '$(git rev-parse --git-common-dir)/gitlore-pre-commit'),
    ('pre-push',   '$(git rev-parse --git-common-dir)/gitlore-pre-push'),
):
```

- [ ] **Step 4: Run the wire suite — lefthook tests green**

Run: `bats tests/hook_manager_wire.bats`
Expected: all lefthook tests PASS (add, idempotent, sentinel, preserves-existing, `.lefthook.yml` filename, no-config-exit-1).

- [ ] **Step 5: Commit**

```bash
git add scripts/hook-manager/wire-lefthook.sh tests/hook_manager_wire.bats
git commit -m "fix: lefthook run command resolves wrapper via git common dir (D11)"
```

---

### Task 6: Gitlink-aware overcommit wiring + the `$@`-forwarding verification test

**Files:**
- Modify: `scripts/hook-manager/wire-overcommit.sh`
- Test: `tests/hook_manager_wire.bats`

> This task settles the one open design decision: overcommit exec's the `command:` array directly and appends staged files as extra argv. The verification test reproduces that invocation exactly and asserts the wrapper receives the files as `"$@"`.

- [ ] **Step 1: Strengthen the overcommit assertions + add the verification test**

In `@test "wire-overcommit adds gitlore PreCommit and PrePush entries"`, after the existing `grep` lines add:

```bash
  grep -qF 'git rev-parse --git-common-dir' .overcommit.yml
```

Then add this new test (`WIRE_OVERCOMMIT` is already defined in the file):

```bash
@test "overcommit command array forwards appended files to the wrapper as \$@ (D11 verification)" {
  cat > .overcommit.yml <<'EOF'
PreCommit:
  RuboCop:
    enabled: true
EOF
  bash "$WIRE_OVERCOMMIT"

  # Reproduce overcommit's invocation: it exec's the command array directly
  # (no shell) and appends staged files as extra argv. We swap the embedded
  # wrapper path for a capture stub, then run the array + files and check the
  # stub saw the files — spaces intact — as positional args.
  cap="$TMP_REPO/cap.sh"
  printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$@"\n' > "$cap"
  chmod +x "$cap"

  run python3 - "$cap" <<'PY'
import sys, subprocess, yaml
cap = sys.argv[1]
cmd = yaml.safe_load(open('.overcommit.yml'))['PreCommit']['gitlore']['command']
cmd = [c.replace('"$(git rev-parse --git-common-dir)/gitlore-pre-commit"', '"%s"' % cap) for c in cmd]
out = subprocess.run(cmd + ['a.rb', 'b c.rb'], capture_output=True, text=True)
sys.stdout.write(out.stdout)
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "a.rb" ]
  [ "${lines[1]}" = "b c.rb" ]
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/hook_manager_wire.bats`
Expected: the new assertions/test FAIL — the old script writes `command: [".git/gitlore-pre-commit"]` (no `sh -c`, no common-dir), so the python `.replace(...)` finds nothing and the array isn't a runnable `sh -c` form.

- [ ] **Step 3: Update both overcommit code paths to the `sh -c` array**

In `scripts/hook-manager/wire-overcommit.sh`, in the **yq** branch replace:

```bash
  yq -i '.PreCommit.gitlore.enabled = true | .PreCommit.gitlore.command = [".git/gitlore-pre-commit"]' "$CONFIG"
  yq -i '.PrePush.gitlore.enabled = true | .PrePush.gitlore.command = [".git/gitlore-pre-push"]'       "$CONFIG"
```
with:
```bash
  yq -i '.PreCommit.gitlore.enabled = true | .PreCommit.gitlore.command = ["sh","-c","exec \"$(git rev-parse --git-common-dir)/gitlore-pre-commit\" \"$@\"","gitlore"]' "$CONFIG"
  yq -i '.PrePush.gitlore.enabled = true | .PrePush.gitlore.command = ["sh","-c","exec \"$(git rev-parse --git-common-dir)/gitlore-pre-push\" \"$@\"","gitlore"]'       "$CONFIG"
```

In the **python3** branch replace the loop body:
```python
for hook, key, wrapper in (
    ('PreCommit', 'gitlore-pre-commit', '.git/gitlore-pre-commit'),
    ('PrePush',   'gitlore-pre-push',   '.git/gitlore-pre-push'),
):
    hook_data = data.setdefault(hook, {})
    # key name used in yaml is just 'gitlore' for both
    hook_data['gitlore'] = {
        'enabled': True,
        'command': [wrapper],
    }
```
with:
```python
for hook, wrapper in (
    ('PreCommit', 'gitlore-pre-commit'),
    ('PrePush',   'gitlore-pre-push'),
):
    hook_data = data.setdefault(hook, {})
    # Overcommit exec's the array directly (no shell); reach the wrapper through
    # an explicit `sh -c`. $0='gitlore'; overcommit appends staged files as $@ (D11).
    hook_data['gitlore'] = {
        'enabled': True,
        'command': [
            'sh', '-c',
            'exec "$(git rev-parse --git-common-dir)/%s" "$@"' % wrapper,
            'gitlore',
        ],
    }
```

- [ ] **Step 4: Run the wire suite — overcommit tests green**

Run: `bats tests/hook_manager_wire.bats`
Expected: all overcommit tests PASS, including the `$@`-forwarding verification test.

- [ ] **Step 5: Commit**

```bash
git add scripts/hook-manager/wire-overcommit.sh tests/hook_manager_wire.bats
git commit -m "fix: overcommit command resolves wrapper via sh -c + git common dir (D11)"
```

---

### Task 7: Update the manual-wiring instructions

**Files:**
- Modify: `scripts/hook-manager/wire-manual.sh`
- Test: `tests/hook_manager_wire.bats`

- [ ] **Step 1: Add an assertion that the printed instructions reference the common-dir wrapper**

In `@test "wire-manual writes a manual sentinel without modifying any files"`, the call uses `run bash "$WIRE_MANUAL"` without `--separate-stderr`, so the instructions go to stderr and aren't captured in `$output`. Add a dedicated test instead:

```bash
@test "wire-manual instructions reference the common-dir wrapper path (D11)" {
  run --separate-stderr bash "$WIRE_MANUAL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"git rev-parse --git-common-dir"* ]]
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bats tests/hook_manager_wire.bats`
Expected: the new manual test FAILS (current instructions say `.git/gitlore-pre-commit`).

- [ ] **Step 3: Update the printed instructions**

In `scripts/hook-manager/wire-manual.sh`, replace the heredoc:

```bash
cat >&2 <<'EOF'

  pre-commit → .git/gitlore-pre-commit
  pre-push   → .git/gitlore-pre-push

Once wired, run /gitlore:install again to re-detect.
EOF
```
with:
```bash
cat >&2 <<'EOF'

  pre-commit → exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"
  pre-push   → exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"

(Resolve the wrapper through the git common dir so it works in linked worktrees.)
Once wired, run /gitlore:install again to re-detect.
EOF
```

- [ ] **Step 4: Run the wire suite — manual tests green**

Run: `bats tests/hook_manager_wire.bats`
Expected: all manual tests PASS, including the new instruction-path test. The "writes a manual sentinel without modifying any files" test is unaffected (still no files created beyond the sentinel).

- [ ] **Step 5: Commit**

```bash
git add scripts/hook-manager/wire-manual.sh tests/hook_manager_wire.bats
git commit -m "docs: manual hook instructions reference git-common-dir wrapper (D11)"
```

---

### Task 8: Session-less-worktree guard in the git hooks

**Files:**
- Modify: `scripts/git-hooks/pre-commit`, `scripts/git-hooks/pre-push`
- Test: `tests/git_hook_pre_commit.bats`, `tests/pre_push_hook.bats`

> When the shared wired hook fires in a linked worktree where no session has run, the memory submodule worktree does not exist. Without a guard, `git -C "$mempath" …` under `set -e` aborts and blocks the commit/push for a *new* reason. The guard makes it a clean no-op.

- [ ] **Step 1: Add the failing pre-commit guard test**

Append to `tests/git_hook_pre_commit.bats`:

```bash
@test "exits 0 in a session-less linked worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]   # git created the gitlink dir but did not init the submodule
  cd "$WT"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  rm -rf "$WT"
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/git_hook_pre_commit.bats`
Expected: the new test FAILS — without the guard the hook reaches `git -C memory …` on a non-existent submodule worktree and exits non-zero.

- [ ] **Step 3: Add the guard to pre-commit**

In `scripts/git-hooks/pre-commit`, immediately after this existing line (near line 19):

```bash
mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""
```
insert:
```bash

# D11 corollary: in a session-less worktree the memory submodule worktree may not
# exist yet. Nothing to sync — never block the parent commit.
if [ -n "$mempath" ] && [ ! -e "$mempath/.git" ]; then
  exit 0
fi
```

(The `if` form is used deliberately — a bare `A && B && exit 0` is unsafe under `set -e`.)

- [ ] **Step 4: Run the pre-commit suite — green**

Run: `bats tests/git_hook_pre_commit.bats`
Expected: all tests PASS, including the new guard test and all pre-existing ones (clean, dirty, commit-and-push, divergence, detached, leaked-GIT_DIR).

- [ ] **Step 5: Add the failing pre-push guard test**

Append to `tests/pre_push_hook.bats` (it loads `helpers/fixtures` and defines `HOOK`; mirror its existing setup):

```bash
@test "exits 0 in a session-less linked worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  rm -rf "$WT"
}
```

> Before writing, open `tests/pre_push_hook.bats` and confirm `HOOK`, `setup`, and the `make_parent_with_memory`/`CLAUDE_PLUGIN_ROOT` conventions match `git_hook_pre_commit.bats`; adjust the variable name if the file uses a different one.

- [ ] **Step 6: Run to confirm failure**

Run: `bats tests/pre_push_hook.bats`
Expected: the new test FAILS.

- [ ] **Step 7: Add the same guard to pre-push**

In `scripts/git-hooks/pre-push`, immediately after this existing line (near line 18):

```bash
mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""
```
insert:
```bash

# D11 corollary: in a session-less worktree the memory submodule worktree may not
# exist yet. Nothing to push — never block the parent push.
if [ -n "$mempath" ] && [ ! -e "$mempath/.git" ]; then
  exit 0
fi
```

- [ ] **Step 8: Run the pre-push suite — green**

Run: `bats tests/pre_push_hook.bats`
Expected: all tests PASS.

- [ ] **Step 9: Commit**

```bash
git add scripts/git-hooks/pre-commit scripts/git-hooks/pre-push tests/git_hook_pre_commit.bats tests/pre_push_hook.bats
git commit -m "fix: pre-commit/pre-push no-op in session-less worktrees (D11)"
```

---

### Task 9: Advisory `WorktreeRemove` hook

**Files:**
- Create: `scripts/cc-hooks/worktree-remove.sh`
- Modify: `hooks/hooks.json`, `Makefile`
- Test: `tests/cc_hook_worktree_remove.bats`

- [ ] **Step 1: Write the new test file (red)**

Create `tests/cc_hook_worktree_remove.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/worktree-remove.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

@test "no-op when no gitlore-memory submodule is registered" {
  run bash "$HOOK" <<<'{"worktree_path":"/tmp/does-not-matter"}'
  [ "$status" -eq 0 ]
}

@test "no-op when worktree_path is missing from input" {
  make_parent_with_memory
  run bash "$HOOK" <<<'{}'
  [ "$status" -eq 0 ]
}

@test "removes the memory worktree SessionStart created for a linked worktree" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"
  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 bash "$SESSION_START"
  [ -e "$WT/memory/.git" ]

  mem_gitdir="$TMP_REPO/.git/modules/gitlore-memory"
  git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"

  run bash "$HOOK" <<<"{\"worktree_path\":\"$WT\"}"
  [ "$status" -eq 0 ]
  ! git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"
}

@test "prunes a dangling memory worktree when the parent dir is already gone" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"
  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 bash "$SESSION_START"

  mem_gitdir="$TMP_REPO/.git/modules/gitlore-memory"
  rm -rf "$WT"   # parent worktree dir removed before the hook fires
  run bash "$HOOK" <<<"{\"worktree_path\":\"$WT\"}"
  [ "$status" -eq 0 ]
  ! git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"
  WT=""          # already removed; skip teardown rm
}
```

- [ ] **Step 2: Run to confirm the file fails (script missing)**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; bats tests/cc_hook_worktree_remove.bats`
Expected: tests FAIL — `worktree-remove.sh` does not exist yet.

- [ ] **Step 3: Write `worktree-remove.sh`**

Create `scripts/cc-hooks/worktree-remove.sh`:

```bash
#!/usr/bin/env bash
# WorktreeRemove (advisory) — tear down the memory submodule worktree that
# gitlore created for a parent worktree. CC cannot be blocked by this hook; on
# any failure it warns and exits 0. Input stdin: {worktree_path} (CC 2.1.150 —
# no branch field). See design.md "WorktreeRemove".
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

input=$(cat)
worktree_path=$(printf '%s' "$input" | jq -r '.worktree_path // empty')
[ -n "$worktree_path" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$PWD}"

# Guard: no-op unless this repo registers the gitlore-memory submodule.
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)

common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
[ -d "$mem_gitdir" ] || exit 0

mem_wt="$worktree_path/$mempath"
if [ -e "$mem_wt" ]; then
  git -C "$mem_gitdir" worktree remove --force "$mem_wt" 2>/dev/null \
    || echo "gitlore: could not remove memory worktree at $mem_wt (locked or uncommitted); it will be pruned." >&2
fi
# Prune dangling admin entries whether the dir was removable or already gone.
git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true

# Branch retention is a deliberate no-op: CC keeps the parent branch on removal
# (verified 2.1.150), so gitlore keeps the memory branch. Never touch parent branches.
exit 0
```

- [ ] **Step 4: Make it executable + register in `hooks/hooks.json`**

```bash
chmod +x scripts/cc-hooks/worktree-remove.sh
```

In `hooks/hooks.json`, add a `WorktreeRemove` entry as a sibling of `SessionStart` and `PostToolUse`:

```json
    "WorktreeRemove": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/worktree-remove.sh"
          }
        ]
      }
    ]
```

(Add a comma after the closing `]` of the `PostToolUse` array so the JSON stays valid.)

- [ ] **Step 5: Run the new suite — green**

Run: `bats tests/cc_hook_worktree_remove.bats`
Expected: all four tests PASS.

- [ ] **Step 6: Validate hooks.json is still valid JSON**

Run: `jq . hooks/hooks.json >/dev/null && echo OK`
Expected: `OK`.

- [ ] **Step 7: Add the new test file to the Makefile**

In `Makefile`, append `tests/cc_hook_worktree_remove.bats` to the end of the `test-unit:` `bats …` line.

- [ ] **Step 8: Commit**

```bash
git add scripts/cc-hooks/worktree-remove.sh hooks/hooks.json Makefile tests/cc_hook_worktree_remove.bats
git commit -m "feat: advisory WorktreeRemove hook tears down the memory worktree"
```

---

### Task 10: Full-suite verification + docs sync

**Files:**
- Modify: `docs/design.md` (changelog), `memory/project_overview.md` (status)

- [ ] **Step 1: Run the entire test suite**

Run: `export PATH="/tmp/claude-1000/bats-core/bin:$PATH"; make test`
Expected: every suite PASSES. If `tests/plugin_distribution.bats` enumerates hook events, confirm it accepts the new `WorktreeRemove` key; if it asserts an exact event set, update that assertion to include `WorktreeRemove` and re-run.

- [ ] **Step 2: Append a changelog row to `docs/design.md`**

Add to the Changelog table:

```markdown
| 2026-05-25 | **Implemented D11.** All five hook managers (direct, husky, lefthook, overcommit, manual) and `emit-wrappers` now anchor the wrapper at `$(git rev-parse --git-common-dir)/gitlore-<hook>`; direct wiring resolves the hook file via `--git-path hooks/<hook>`. `pre-commit`/`pre-push` early-exit in session-less worktrees (`[ -e "$mempath/.git" ]`). SessionStart lazily creates the memory submodule worktree; new advisory `WorktreeRemove` hook removes it. Overcommit's `sh -c` array `$@`-forwarding verified by test. |
```

- [ ] **Step 3: Update `memory/project_overview.md` current-state line**

Update the "Plan 06 superseded → D11" paragraph to note D11 is now **implemented and tested** (Plan 07), not just designed. Keep it to a sentence or two; record the smaller deferred items that remain.

- [ ] **Step 4: Commit (memory submodule first, then root — see memory rule)**

```bash
# If memory/ has changes, commit them inside the submodule first.
git -C memory add -A && git -C memory commit -m "memory: D11 implemented" || true
git add docs/design.md memory
git commit -m "docs: record D11 implementation (Plan 07)"
```

---

## Self-Review

**Spec coverage (D11 + absorbed Plan 06):**
- Common-dir anchor on the **write** side → Task 1 (emit-wrappers). ✓
- Common-dir anchor on the **exec** side across all five managers → Tasks 3 (direct), 4 (husky), 5 (lefthook), 6 (overcommit), 7 (manual). ✓
- Direct hook file via `--git-path hooks/<hook>` → Task 3. ✓
- Early `[ -e "$mempath/.git" ] || exit 0` in pre-commit/pre-push → Task 8. ✓
- Overcommit `sh -c` array with verified `$@` forwarding (the open decision) → Task 6. ✓
- SessionStart memory-worktree creation → Task 2 (folds in working-tree edit). ✓
- Advisory `WorktreeRemove` → Task 9. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full content; every test step shows the test and the run command with expected result.

**Type/name consistency:** `GITLORE_SUBMODULE_NAME` (from `util.sh`), `gitlore_has_submodule`/`gitlore_memory_path` (util.sh), `mem_gitdir = <common-dir>/modules/gitlore-memory`, `# gitlore: managed` marker, sentinel values (`direct`/`npx husky`/`lefthook install`/`overcommit --install`/`manual`) all used consistently with the existing code. The wrapper exec form `exec "$(git rev-parse --git-common-dir)/gitlore-<hook>" "$@"` is identical across direct, husky, overcommit (inside `sh -c`), and the manual instructions.

**Ordering dependency:** Task 1 must precede Tasks 2 and 9 (both need emit-wrappers fixed for SessionStart to succeed in a linked worktree). Tasks 3-8 are independent of each other and of 1/2, but all touch `tests/hook_manager_wire.bats` (3-7), so run them sequentially to avoid edit conflicts.
