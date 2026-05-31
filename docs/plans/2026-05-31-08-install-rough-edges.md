# Install Rough Edges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix seven install rough edges from the 0.2.1 bug report — making the installer robust under the Claude Code Bash tool, sandbox-aware, design-compliant for remote creation, and upgrade-safe for hook wrappers.

**Architecture:** Pure shell + bats. Scripts self-locate `CLAUDE_PLUGIN_ROOT` instead of trusting the environment; a write-capability probe fails loudly with a paste-able command; `create-remote.sh` becomes a mode dispatcher (opportunistic-gh / existing-URL / local-only) honoring FR9/FR10/D8 and the `<parent-remote-name>-memory` naming rule; the hook wrapper degrades to a clean skip when its version-pinned hooks dir was GC'd after a plugin upgrade.

**Tech Stack:** bash, bats-core, git, gh (opportunistic), jq.

**Scope note:** These are independent fixes to one subsystem (install). They are ordered low-risk-first (Tasks 1–4: #1, #9, #7, #2), then the larger remote rewrite (Tasks 5–8: #5/#6). Each task ends green and committed.

**Design references:** `docs/design.md` — FR9 (provider-agnostic remote), FR10 + D8 (disclosure + confirmation), Remote Repository → Naming/Visibility/Creation method, D5 (wrapper degradation), D7 (scripts decide). The D5 stale-dir extension and this sweep are recorded in the 2026-05-31 changelog row.

**Conventions discovered (follow exactly):**
- Tests live in `tests/*.bats`, load `helpers/setup` (provides `setup_tmp_repo`/`teardown_tmp_repo`, exports `PLUGIN_ROOT`, `TMP_REPO`) and `helpers/gh-mock` (`install_gh_mock`, scripted via `GH_MOCK_*` env vars).
- `setup_tmp_repo` does `git init -q -b main` with **no origin remote** — so naming/visibility helpers must exercise their no-parent-remote fallback in tests.
- Run a single test file: `bats tests/<file>.bats`. Full suite: `bats tests/`.
- Library functions go in `scripts/lib/util.sh` (sourced by both install scripts and hot-path hooks — keep them dependency-light).

---

## Task 1: Self-locate `CLAUDE_PLUGIN_ROOT` (#1)

**Files:**
- Modify: `scripts/install/run.sh:7`
- Modify: `scripts/install/create-remote.sh:9`
- Modify: `scripts/install/emit-launcher.sh:4`
- Modify: `scripts/install/write-settings.sh:30`
- Test: `tests/install_run.bats`

The four scripts read `${CLAUDE_PLUGIN_ROOT:?...}` from the environment, which is **unset** under the Claude Code Bash tool (that var is injected for hooks, not Bash commands). `run.sh` self-locates and exports it for its children; the children keep a self-locating fallback so they also work when invoked standalone (as the tests do).

- [ ] **Step 1: Write the failing test**

Add to `tests/install_run.bats` (after the existing `run.sh completes a full local install` test):

```bash
@test "run.sh self-locates CLAUDE_PLUGIN_ROOT when unset in env" {
  unset CLAUDE_PLUGIN_ROOT
  run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -f .claude/settings.json ]
  [ -d memory ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/install_run.bats -f "self-locates"`
Expected: FAIL — `run.sh: line 7: CLAUDE_PLUGIN_ROOT: CLAUDE_PLUGIN_ROOT must be set`, status 1.

- [ ] **Step 3: Implement self-location in run.sh**

Replace `scripts/install/run.sh:7`:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
```

with:

```bash
# Self-locate so we work under the Claude Code Bash tool, where
# CLAUDE_PLUGIN_ROOT is injected for hooks but NOT for Bash commands.
# Export it so the child install scripts inherit a correct value.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
```

- [ ] **Step 4: Implement self-location fallback in the three children**

In `scripts/install/create-remote.sh:9`, replace:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
```

with:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
```

In `scripts/install/emit-launcher.sh:4`, replace:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
```

with:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
```

In `scripts/install/write-settings.sh:30`, replace:

```bash
git config gitlore.hooksDir "${CLAUDE_PLUGIN_ROOT}/scripts/git-hooks"
```

with:

```bash
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
git config gitlore.hooksDir "${plugin_root}/scripts/git-hooks"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/install_run.bats -f "self-locates"`
Expected: PASS.

- [ ] **Step 6: Run the full install suites to check no regression**

Run: `bats tests/install_run.bats tests/install_remote.bats tests/emit_launcher.bats`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/install/run.sh scripts/install/create-remote.sh scripts/install/emit-launcher.sh scripts/install/write-settings.sh tests/install_run.bats
git commit -m "fix: self-locate CLAUDE_PLUGIN_ROOT in install scripts"
```

---

## Task 2: Stray blank line in `.gitignore` (#9)

**Files:**
- Modify: `scripts/install/write-settings.sh:22-24`
- Test: `tests/install_run.bats`

`write-settings.sh:24` appends `printf '\n.claude/settings.local.json\n'` to an existing `.gitignore`, leaving a stray blank line. Append the line cleanly.

- [ ] **Step 1: Write the failing test**

Add to `tests/install_run.bats`:

```bash
@test "install does not leave a stray blank line in .gitignore" {
  printf 'node_modules\n' > .gitignore
  bash "$RUN_INSTALL" memory "echo pc"
  # No empty lines anywhere in the resulting .gitignore.
  ! grep -qxE '' .gitignore
  grep -qx '.claude/settings.local.json' .gitignore
  grep -qx 'node_modules' .gitignore
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/install_run.bats -f "stray blank line"`
Expected: FAIL — `! grep -qxE ''` fails because a blank line is present.

- [ ] **Step 3: Fix the append**

In `scripts/install/write-settings.sh`, replace lines 22-27:

```bash
if [ -f .gitignore ]; then
  grep -qx '.claude/settings.local.json' .gitignore || \
    printf '\n.claude/settings.local.json\n' >> .gitignore
else
  printf '.claude/settings.local.json\n' > .gitignore
fi
```

with:

```bash
if [ -f .gitignore ]; then
  # Append a trailing newline first only if the file does not already end in one,
  # so we never introduce a blank line.
  if [ -n "$(tail -c1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  grep -qx '.claude/settings.local.json' .gitignore || \
    printf '.claude/settings.local.json\n' >> .gitignore
else
  printf '.claude/settings.local.json\n' > .gitignore
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/install_run.bats -f "stray blank line"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/install/write-settings.sh tests/install_run.bats
git commit -m "fix: no stray blank line when appending to .gitignore"
```

---

## Task 3: Wrapper degrades on a stale (GC'd) hooks dir (#7)

**Files:**
- Modify: `scripts/emit-wrappers.sh:14-23` (the heredoc wrapper body)
- Test: `tests/emit_wrappers.bats`

`emit-wrappers.sh` writes wrappers that `exec "$HOOKS_DIR/<hook>"` where `$HOOKS_DIR` is the version-pinned `gitlore.hooksDir`. After a plugin upgrade the old cache dir is GC'd; in the window before the next SessionStart re-pins the config, a plain-terminal commit `exec`s a missing path and **hard-fails**. Add a guard: if `$HOOKS_DIR/<hook>` is not executable, skip with a hint (exit 0). Matches design.md D5 (two-case degradation).

- [ ] **Step 1: Write the failing test**

Add to `tests/emit_wrappers.bats` (after the `wrapper execs the real hook` test):

```bash
@test "wrapper exits 0 with hint when gitlore.hooksDir is set but GC'd" {
  bash "$EMIT"
  # Point hooksDir at a directory that does not contain the hook (simulates a
  # plugin upgrade that GC'd the old version's cache before SessionStart re-pins).
  git config gitlore.hooksDir "$TMP_REPO/gone-cache/scripts/git-hooks"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]]
  [[ "$output" == *"stale"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/emit_wrappers.bats -f "GC'd"`
Expected: FAIL — the wrapper `exec`s the missing path; status is non-zero (127 / "not found"), no "stale" message.

- [ ] **Step 3: Add the guard to the wrapper heredoc**

In `scripts/emit-wrappers.sh`, replace the `write_wrapper` heredoc body (lines 14-23):

```bash
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
```

with:

```bash
  cat > "$out" <<EOF
#!/usr/bin/env sh
HOOKS_DIR=\$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "\$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "\$HOOKS_DIR/$hook" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Start Claude Code in this repo to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "\$HOOKS_DIR/$hook" "\$@"
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/emit_wrappers.bats -f "GC'd"`
Expected: PASS.

- [ ] **Step 5: Run the whole wrapper suite (idempotency test compares wrapper bytes)**

Run: `bats tests/emit_wrappers.bats`
Expected: all PASS (the `emit-wrappers is idempotent` test still passes — both emissions produce the identical new body).

- [ ] **Step 6: Commit**

```bash
git add scripts/emit-wrappers.sh tests/emit_wrappers.bats
git commit -m "fix: hook wrapper skips cleanly when hooksDir is stale after upgrade"
```

---

## Task 4: Sandbox write-probe with paste-able fallback (#2)

**Files:**
- Create: helper in `scripts/lib/util.sh` (append `gitlore_probe_writable`)
- Modify: `scripts/install/run.sh` (probe before mutations, after the worktree guards)
- Modify: `commands/install.md` (sandbox guidance)
- Test: `tests/lib_util.bats` (probe helper) and `tests/install_run.bats` (run.sh message)

The installer writes `.gitmodules`, `.git/modules/…`, and pushes — all blocked by the Claude Code command sandbox. The first run died on `.gitmodules: Permission denied` with no hint. Add a writability probe that fails loudly with the exact command to re-run sandbox-disabled.

- [ ] **Step 1: Write the failing test for the probe helper**

Add to `tests/lib_util.bats`:

```bash
@test "gitlore_probe_writable succeeds on a writable dir" {
  run gitlore_probe_writable "$TMP_REPO"
  [ "$status" -eq 0 ]
}

@test "gitlore_probe_writable fails on a read-only dir" {
  local ro="$TMP_REPO/ro"
  mkdir -p "$ro"
  chmod 555 "$ro"
  run gitlore_probe_writable "$ro"
  chmod 755 "$ro"   # restore so teardown can rm -rf
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/lib_util.bats -f "probe_writable"`
Expected: FAIL — `gitlore_probe_writable: command not found`.

- [ ] **Step 3: Implement the probe helper**

Append to `scripts/lib/util.sh`:

```bash
# Exit 0 if $1 is a writable directory, 1 otherwise. Used to detect a sandboxed
# install before it dies mid-mutation with a raw "Permission denied".
# Args: $1 = directory to test.
gitlore_probe_writable() {
  local dir="$1" probe="$1/.gitlore-write-probe.$$"
  if ( : > "$probe" ) 2>/dev/null; then
    rm -f "$probe"
    return 0
  fi
  return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/lib_util.bats -f "probe_writable"`
Expected: PASS.

- [ ] **Step 5: Write the failing test for run.sh's loud failure**

Add to `tests/install_run.bats`:

```bash
@test "run.sh fails loudly with a paste-able command when repo root is unwritable" {
  # Make the git common dir unwritable so the probe trips before any mutation.
  chmod 555 .git
  run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  chmod 755 .git   # restore for teardown
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"sandbox"* ]]
  [[ "$stderr" == *"$RUN_INSTALL"* ]]
  # Nothing was created before the loud failure.
  [ ! -d memory ]
  [ ! -f .claude/settings.json ]
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bats tests/install_run.bats -f "paste-able"`
Expected: FAIL — run.sh currently proceeds and dies later with a raw error (or partially succeeds), not the sandbox message.

- [ ] **Step 7: Add the probe to run.sh**

In `scripts/install/run.sh`, insert after the linked-worktree guard block (immediately before `bash "$PLUGIN_ROOT/scripts/install/preflight.sh"` at line 29):

```bash
# Sandbox probe: the install writes .gitmodules at the repo root and absorbs the
# submodule gitdir under the git common dir, then pushes a remote. Under the
# Claude Code command sandbox these writes fail with a raw "Permission denied"
# mid-run, leaving partial state. Detect it up front and fail with the exact
# command to re-run sandbox-disabled.
common_dir_abs=$(cd "$(git rev-parse --git-common-dir)" && pwd)
for probe_dir in "$toplevel" "$common_dir_abs"; do
  if ! gitlore_probe_writable "$probe_dir"; then
    {
      echo "gitlore: cannot write to '$probe_dir' — the command sandbox is blocking install."
      echo "gitlore: re-run with the sandbox disabled:"
      echo "  CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT' bash '${BASH_SOURCE[0]}' '$mempath' '$precommit_cmd'"
    } >&2
    exit 3
  fi
done
```

(`gitlore_probe_writable` is already in scope: `run.sh:10` sources `scripts/lib/util.sh`.)

- [ ] **Step 8: Run test to verify it passes**

Run: `bats tests/install_run.bats -f "paste-able"`
Expected: PASS.

- [ ] **Step 9: Add sandbox guidance to install.md**

In `commands/install.md`, replace step 2's body:

```markdown
2. **Run the installer.**
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"
   ```
   Surface stderr verbatim on non-zero exit and stop. Relay stdout and stderr to the user on success.
```

with:

```markdown
2. **Run the installer.** This step writes `.gitmodules`, absorbs the memory
   submodule gitdir under `.git/`, and pushes a remote — all of which the Claude
   Code command sandbox blocks. Run it with the sandbox **disabled**.
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"
   ```
   If it exits non-zero with a "command sandbox is blocking install" message,
   re-run the exact command it prints (the same invocation, sandbox disabled).
   Surface stderr verbatim on non-zero exit and stop. Relay stdout and stderr to
   the user on success.
```

- [ ] **Step 10: Commit**

```bash
git add scripts/lib/util.sh scripts/install/run.sh commands/install.md tests/lib_util.bats tests/install_run.bats
git commit -m "feat: probe write capability before install, fail with paste-able command"
```

---

## Task 5: Memory remote naming + visibility helpers (#5/#6 groundwork)

**Files:**
- Modify: `scripts/lib/util.sh` (append `gitlore_memory_remote_name`, `gitlore_parent_visibility`)
- Test: `tests/lib_util.bats`

design.md (Remote Repository → Naming) specifies `<parent-remote-name>-memory` derived from the parent's `origin` URL — the current code derives from the local directory basename (`create-remote.sh:19`), which drifts if a repo is cloned into a differently-named directory. Add helpers that parse the parent origin URL (with a repo-basename fallback when there is no origin), and that read the parent's visibility (default private).

- [ ] **Step 1: Write the failing tests for naming**

Add to `tests/lib_util.bats`:

```bash
@test "gitlore_memory_remote_name from https origin" {
  git remote add origin "https://github.com/acme/project.git"
  run gitlore_memory_remote_name
  [ "$status" -eq 0 ]
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name from scp-style origin" {
  git remote add origin "git@github.com:acme/project.git"
  run gitlore_memory_remote_name
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name from origin without .git suffix" {
  git remote add origin "https://github.com/acme/project"
  run gitlore_memory_remote_name
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name falls back to repo basename when no origin" {
  # setup_tmp_repo created the repo with no origin; the dir basename is the temp name.
  run gitlore_memory_remote_name
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$TMP_REPO")-memory" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/lib_util.bats -f "remote_name"`
Expected: FAIL — `gitlore_memory_remote_name: command not found`.

- [ ] **Step 3: Implement the naming helper**

Append to `scripts/lib/util.sh`:

```bash
# Print the memory remote's bare name: <parent-remote-base>-memory.
# Derives the base from the parent repo's origin URL when set, handling both
# https (.../owner/repo[.git]) and scp-style (git@host:owner/repo[.git]) forms,
# with or without a trailing .git. Falls back to the repo directory basename when
# there is no origin (so the name is stable regardless of the local dir name when
# a remote exists — fixing the clone-dir-rename drift).
gitlore_memory_remote_name() {
  local url base
  url=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$url" ]; then
    base=${url##*/}                       # https or scp-with-slash → repo[.git]
    case "$base" in *:*) base=${base##*:};; esac  # scp without a slash
    base=${base%.git}
  else
    base=$(basename "$(git rev-parse --show-toplevel)")
  fi
  printf '%s-memory\n' "$base"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/lib_util.bats -f "remote_name"`
Expected: all PASS.

- [ ] **Step 5: Write the failing test for visibility**

Add to `tests/lib_util.bats`:

```bash
@test "gitlore_parent_visibility defaults to private with no origin" {
  run gitlore_parent_visibility
  [ "$status" -eq 0 ]
  [ "$output" = "private" ]
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bats tests/lib_util.bats -f "parent_visibility"`
Expected: FAIL — `gitlore_parent_visibility: command not found`.

- [ ] **Step 7: Implement the visibility helper**

Append to `scripts/lib/util.sh`:

```bash
# Print the visibility to use for the memory remote: "public" or "private".
# Matches the parent repo (design: public parent → public memory). Defaults to
# "private" when there is no parent origin or gh cannot report it — the safe
# default for memory, which may contain session context.
gitlore_parent_visibility() {
  local purl v
  purl=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$purl" ] && command -v gh >/dev/null 2>&1; then
    v=$(gh repo view "$purl" --json visibility -q .visibility 2>/dev/null \
          | tr 'A-Z' 'a-z' || true)
    [ "$v" = "public" ] && { printf 'public\n'; return 0; }
  fi
  printf 'private\n'
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bats tests/lib_util.bats -f "parent_visibility"`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add scripts/lib/util.sh tests/lib_util.bats
git commit -m "feat: memory-remote naming + visibility helpers (parent-origin-derived)"
```

---

## Task 6: `create-remote.sh` becomes a mode dispatcher (#5/#6)

**Files:**
- Modify: `scripts/install/create-remote.sh` (full rewrite of the creation logic)
- Modify: `scripts/install/run.sh:45` (pass the remote mode/url through)
- Test: `tests/install_remote.bats`

Rewrite `create-remote.sh` to honor design.md's Remote Repository section: opportunistic gh (parent-matched visibility, parent-derived name), existing-URL wiring for any host, and first-class local-only. The confirmation gate (D8) lives in install.md (Task 8); this script is the non-interactive executor of the already-decided mode.

**Interface:** `create-remote.sh <mempath> [mode] [url]`
- `mode` = `auto` (default): use gh if available **and** authed → create+push+wire; otherwise leave the placeholder (local-only) with a notice.
- `mode` = `url`: `git remote add origin <url>`, push `live`, wire `.gitmodules`.
- `mode` = `local`: leave the placeholder URL, print a local-only notice, exit 0.

`run.sh` gains a 3rd arg (`remote_mode`, default `auto`) and a 4th (`remote_url`), forwarded to `create-remote.sh`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/install_remote.bats`:

```bash
@test "auto mode with no gh leaves a local-only install (placeholder URL kept)" {
  # Build a PATH without gh but with the tools run.sh needs.
  local no_gh_bin="$TMP_REPO/.no-gh-bin"
  mkdir -p "$no_gh_bin"
  for tool in bash sh git jq mktemp dirname basename find grep sed awk sort cat cp rm mkdir touch chmod tail stat; do
    bin=$(command -v "$tool" 2>/dev/null || true)
    [ -n "$bin" ] && ln -sf "$bin" "$no_gh_bin/$tool"
  done
  PATH="$no_gh_bin" run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [[ "$stderr" == *"local-only"* ]]
}

@test "url mode wires an existing remote and pushes live" {
  local remote="$TMP_REPO/.existing-remote.git"
  git init -q --bare "$remote"
  bash "$RUN_INSTALL" memory "echo pc" url "$remote"
  url=$(git -C memory config --get remote.origin.url)
  [ "$url" = "$remote" ]
  # live was pushed to the existing remote.
  git -C "$remote" show-ref --verify --quiet refs/heads/live
  gm=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [ "$gm" = "$remote" ]
}

@test "local mode keeps placeholder and never calls gh" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc" local
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [ ! -f "$log" ] || ! grep -q 'repo create' "$log"
}

@test "auto mode (gh available) names the remote <parent-base>-memory" {
  git remote add origin "https://github.com/acme/project.git"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc"
  grep -q 'repo create' "$log"
  grep -q 'project-memory' "$log"
}
```

Also **update the existing preflight tests** at `tests/install_remote.bats:42-66` — gh is now opportunistic, not required, so they must assert local-only completion instead of abort. Replace the `preflight aborts install when gh is missing` and `preflight aborts install when gh is unauthed` tests with:

```bash
@test "install completes local-only when gh is unauthed (no abort)" {
  GH_MOCK_EXIT_AUTH_STATUS=1 run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
}
```

(The `gh missing` case is now covered by the `auto mode with no gh` test above.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/install_remote.bats`
Expected: the new `auto mode with no gh`, `url mode`, `local mode`, `<parent-base>-memory`, and `local-only when gh unauthed` tests FAIL (current `create-remote.sh` ignores mode args, always tries gh, and `preflight.sh` aborts when gh is missing/unauthed).

- [ ] **Step 3: Drop the gh hard-abort from preflight.sh**

In `scripts/install/preflight.sh`, replace lines 6-18 (the gh-not-found and gh-unauthed hard aborts):

```bash
if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' CLI not found. Install it from https://cli.github.com/, then re-run /gitlore:install.
EOF
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' is not authenticated. Run 'gh auth login', then re-run /gitlore:install.
EOF
  exit 1
fi
```

with:

```bash
# gh is opportunistic (FR9): a missing or unauthed gh is NOT a hard failure —
# install falls back to local-only and the user can add a remote later. Only
# emit an advisory note so the agent can offer the gh path if desired.
if ! command -v gh >/dev/null 2>&1; then
  echo "gitlore: 'gh' CLI not found — proceeding; remote creation will be local-only unless a URL is supplied." >&2
elif ! gh auth status >/dev/null 2>&1; then
  echo "gitlore: 'gh' is not authenticated — proceeding; remote creation will be local-only unless a URL is supplied." >&2
fi
```

(Leave the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` block and `exit 0` intact.)

- [ ] **Step 4: Rewrite create-remote.sh as a mode dispatcher**

Replace the body of `scripts/install/create-remote.sh` (everything after the `source` of `util.sh`, i.e. from line 13 to the end) with:

```bash
mode="${2:-auto}"
url_arg="${3:-}"

# Idempotency: a real (non-placeholder) origin already wired → nothing to do.
existing=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "./.git/gitlore-placeholder" ]; then
  exit 0
fi

wire_and_push() {
  # Args: $1 = remote URL. Adds origin, pushes live, rewrites .gitmodules URL.
  local remote_url="$1"
  git -C "$mempath" remote add origin "$remote_url"
  if ! git -C "$mempath" push -u origin live; then
    echo "gitlore: wired remote but failed to push memory's live branch. Run /gitlore:resolve to retry." >&2
    exit 1
  fi
  git config --file .gitmodules "submodule.${GITLORE_SUBMODULE_NAME}.url" "$remote_url"
  git add .gitmodules
}

local_only_notice() {
  echo "gitlore: installed local-only — memory is versioned in-repo with no remote." >&2
  echo "gitlore: add a remote later by re-running /gitlore:install and supplying a URL." >&2
}

case "$mode" in
  url)
    [ -n "$url_arg" ] || { echo "gitlore: url mode requires a remote URL." >&2; exit 1; }
    wire_and_push "$url_arg"
    ;;

  local)
    local_only_notice
    ;;

  auto)
    # Opportunistic gh: only when present AND authenticated.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      owner=$(gh api user -q .login)
      repo_name=$(gitlore_memory_remote_name)
      visibility=$(gitlore_parent_visibility)
      full_name="${owner}/${repo_name}"
      if ! gh repo create "$full_name" --"$visibility"; then
        echo "gitlore: gh repo create failed. Run /gitlore:resolve to recover, or re-run install with a remote URL." >&2
        exit 1
      fi
      remote_url=$(gh repo view "$full_name" --json sshUrl -q .sshUrl || true)
      if [ -z "$remote_url" ]; then
        echo "gitlore: created remote $full_name but could not resolve its URL. Run /gitlore:resolve to recover." >&2
        exit 1
      fi
      wire_and_push "$remote_url"
    else
      # No usable gh → local-only (the agent offers the copy-paste URL path
      # interactively in install.md before reaching this non-interactive script).
      local_only_notice
    fi
    ;;

  *)
    echo "gitlore: unknown remote mode '$mode'." >&2
    exit 1
    ;;
esac

exit 0
```

- [ ] **Step 5: Forward the mode/url args from run.sh**

In `scripts/install/run.sh`, add argument capture near the top (after line 5, `precommit_cmd="${2:-}"`):

```bash
remote_mode="${3:-auto}"
remote_url="${4:-}"
```

Then replace line 45:

```bash
bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
```

with:

```bash
bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath" "$remote_mode" "$remote_url"
```

- [ ] **Step 6: Run the remote suite to verify it passes**

Run: `bats tests/install_remote.bats`
Expected: all PASS, including the existing `install rewrites .gitmodules URL`, `records gh repo create`, `aborts cleanly when gh repo create fails`, and `idempotent` tests (auto mode is the default, so they exercise the gh path unchanged — except the name is now `<parent-base>-memory`; the existing `--private` assertion still holds because the test repo has no parent origin → visibility defaults to private).

- [ ] **Step 7: Run the full suite to catch cross-file regressions**

Run: `bats tests/`
Expected: all PASS. Pay attention to `tests/integration_clone_restore.bats` and `tests/integration_happy_path.bats`, which run the full install flow.

- [ ] **Step 8: Commit**

```bash
git add scripts/install/create-remote.sh scripts/install/run.sh scripts/install/preflight.sh tests/install_remote.bats
git commit -m "feat: provider-agnostic remote creation (auto/url/local) per FR9/FR10"
```

---

## Task 7: gh-mock supports the visibility query (test-fidelity)

**Files:**
- Modify: `tests/helpers/gh-mock.bash`
- Test: `tests/install_remote.bats` (a visibility-matching test)

`gitlore_parent_visibility` calls `gh repo view <url> --json visibility -q .visibility`. The current mock returns `GH_MOCK_REMOTE_URL` for any `repo view`, so a visibility query returns a URL string (→ not "public" → private), which is correct-by-accident. Make it explicit so a future public-parent test is possible and the mock's intent is clear.

- [ ] **Step 1: Write the failing test**

Add to `tests/install_remote.bats`:

```bash
@test "auto mode creates a public remote when the parent is public" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY="PUBLIC"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc"
  grep -q -- '--public' "$log"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/install_remote.bats -f "public remote"`
Expected: FAIL — the mock returns the URL for `repo view`, so visibility resolves to private and `--public` is never logged.

- [ ] **Step 3: Teach the mock the visibility query**

In `tests/helpers/gh-mock.bash`, after the existing `repo view ... sshUrl` block (the `if [ -z "$stdout_val" ] && [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && [ -n "${GH_MOCK_REMOTE_URL:-}" ]` block), add:

```bash
# `gh repo view <url> --json visibility -q .visibility` → configured visibility.
# Checked before the sshUrl fallback by matching on the --json argument.
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && \
   printf '%s\n' "$@" | grep -q 'visibility' && [ -n "${GH_MOCK_VISIBILITY:-}" ]; then
  printf '%s\n' "$GH_MOCK_VISIBILITY"
  exit 0
fi
```

Place this block **before** the line `[ -n "$stdout_val" ] && printf '%s\n' "$stdout_val"` and before the sshUrl block so the visibility query is answered specifically. If ordering against the sshUrl block is awkward, gate the sshUrl block to also require the `sshUrl` argument:

```bash
if [ -z "$stdout_val" ] && [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && \
   printf '%s\n' "$@" | grep -q 'sshUrl' && [ -n "${GH_MOCK_REMOTE_URL:-}" ]; then
  stdout_val="$GH_MOCK_REMOTE_URL"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/install_remote.bats -f "public remote"`
Expected: PASS.

- [ ] **Step 5: Run the remote suite to confirm no regression**

Run: `bats tests/install_remote.bats`
Expected: all PASS (the default-private tests still resolve to private because `GH_MOCK_VISIBILITY` is unset there).

- [ ] **Step 6: Commit**

```bash
git add tests/helpers/gh-mock.bash tests/install_remote.bats
git commit -m "test: gh-mock answers the repo-visibility query explicitly"
```

---

## Task 8: install.md — disclosure + D8 confirmation + remote-mode selection (#5/#6 agent side)

**Files:**
- Modify: `commands/install.md`
- (No bats — this is the agent-facing contract; verified by reading, per D7 the script side is what tests cover.)

design.md FR10 + D8 require: before creating the remote, show the user the proposed name/owner/visibility and a session-context notice, and get explicit confirmation. Per D7 the *decision* is the agent's; the *execution* is `create-remote.sh`. install.md must drive the mode selection and pass it to `run.sh`.

- [ ] **Step 1: Rewrite install.md to add input + confirmation steps**

Replace the entire body of `commands/install.md` (keep the frontmatter) with:

```markdown
# /gitlore:install

1. **Gather inputs.** Use `$1` as the memory path if supplied, otherwise ask the user (default: `memory`). Use `$2` as the precommit command if supplied, otherwise ask the user (e.g. `lefthook run pre-commit`, `pre-commit run --all-files`).

2. **Choose the memory remote (D8 — explicit confirmation required).** Determine the proposed remote and confirm before any external action:
   - Run `git config --get remote.origin.url` in the repo. If it returns a URL and `gh auth status` succeeds, the default is **auto-create on GitHub**. Compute the proposed name as `<parent-repo-base>-memory` (the parent origin's repo name with `-memory` appended) and the visibility to match the parent (public parent → public, else private). Show the user the full proposal — owner, repository name, visibility — plus this notice:
     > Memory pushed to this remote may contain any context Claude has recorded — project details, decisions, or incidental session content. Each memory commit is reviewed and confirmed before it's pushed, so you control what goes up.
     Ask for explicit confirmation. Treat only a clear affirmative as approval.
   - If the user prefers a different host or already has an empty remote, ask for the clone URL and use **url mode**.
   - If `gh` is unavailable/unauthed and the user has no URL, or the user declines remote creation, use **local-only mode** (memory works in-repo; a remote can be added later).

3. **Run the installer** with the confirmed mode. This step writes `.gitmodules`, absorbs the memory submodule gitdir under `.git/`, and pushes a remote — all of which the Claude Code command sandbox blocks. Run it with the sandbox **disabled**.
   - Auto-create (default): `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"`
   - Existing URL: `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>" url "<remote-url>"`
   - Local-only: `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>" local`

   If it exits non-zero with a "command sandbox is blocking install" message, re-run the exact command it prints (same invocation, sandbox disabled). Surface stderr verbatim on non-zero exit and stop. Relay stdout and stderr to the user on success.
```

- [ ] **Step 2: Self-check the contract against the script**

Run: `bash -n scripts/install/run.sh && bash -n scripts/install/create-remote.sh`
Expected: no syntax errors. Confirm the three documented invocations match `run.sh`'s arg order (`<mempath> <precommit> [mode] [url]`) — they do (Task 6, Step 5).

- [ ] **Step 3: Run the full install integration suite**

Run: `bats tests/install_run.bats tests/install_remote.bats tests/integration_happy_path.bats tests/integration_clone_restore.bats`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add commands/install.md
git commit -m "docs: install.md drives remote-mode selection + D8 confirmation"
```

---

## Task 9: Full-suite verification + design.md cross-check

**Files:** none modified (verification only).

- [ ] **Step 1: Run the entire bats suite**

Run: `bats tests/`
Expected: all green. Note the count and compare to the pre-change baseline (was 153 per the 2026-05-29 changelog; this plan adds ~12 tests and removes/rewrites 2).

- [ ] **Step 2: shellcheck the changed scripts**

Run: `shellcheck scripts/install/run.sh scripts/install/create-remote.sh scripts/install/write-settings.sh scripts/install/emit-launcher.sh scripts/install/preflight.sh scripts/emit-wrappers.sh scripts/lib/util.sh`
Expected: no new warnings (pre-existing disables already annotated). Fix any introduced.

- [ ] **Step 3: Confirm design.md already records this work**

Read `docs/design.md` — the 2026-05-31 changelog row and the D5 two-case wrapper text were added during planning. Verify they still match the implemented behavior (wrapper skips on unset AND stale hooksDir; remote naming is `<parent-base>-memory`; gh is opportunistic). No further design edits expected; if behavior drifted from the changelog text, update the row.

- [ ] **Step 4: Final commit (only if Step 2 required fixes)**

```bash
git add -A
git commit -m "chore: shellcheck cleanups for install rough-edges sweep"
```

---

## Self-Review

**Spec coverage (against the triage + design.md):**
- #1 self-locate `CLAUDE_PLUGIN_ROOT` → Task 1. ✓
- #2 sandbox probe + paste-able command + install.md guidance → Task 4 (+ install.md in Task 8). ✓
- #3 direnv `.envrc` → intentionally **not** done (resolved in 0.2.0; `.envrc` is tracked-by-design per the Configuration table). Documented as out of scope in the plan header. ✓
- #4 plain-repo dead-end → already fixed (detect.sh defaults to `direct`); no task. ✓
- #5 remote confirmation → Task 8 (D8 in install.md). ✓
- #6 provider-agnostic / local-only → Tasks 5–7 (helpers, dispatcher, mock). ✓
- #7 version-pinned hooksDir landmine → Task 3 (wrapper degradation). ✓
- #8 partial-failure retry → already fixed (run.sh resume logic); no task. ✓
- #9 stray `.gitignore` blank line → Task 2. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every test step shows the assertion and the run command with expected result.

**Type/interface consistency:**
- `gitlore_probe_writable` (Task 4) used in run.sh — defined Task 4 Step 3. ✓
- `gitlore_memory_remote_name`, `gitlore_parent_visibility` (Task 5) used in create-remote.sh (Task 6). ✓
- `run.sh` arg order `<mempath> <precommit> [mode] [url]` consistent across Task 6 (Step 5) and Task 8 (Step 1). ✓
- `create-remote.sh <mempath> [mode] [url]` consistent between its rewrite (Task 6 Step 4) and the run.sh call (Task 6 Step 5). ✓
- `GH_MOCK_VISIBILITY` introduced (Task 7) and consumed by the public-remote test (Task 7 Step 1). ✓

**Ordering risk:** Task 6 changes the default remote name from `<repo-basename>-gitlore-memory` to `<parent-base>-memory`. Existing installs are unaffected (idempotency skips when a real origin URL is already wired). New installs get the new name — intended per the "code to match design" decision.
