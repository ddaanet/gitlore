# Plan 05 — Memory Redirect Launcher (D10)

> **For agentic workers:** execute task-by-task with TDD (red → green → commit). Steps use `- [ ]` checkboxes for tracking. Each step lists exact files, code, and commands.

**Goal:** Build the transparent `claude` shim that injects `--settings '{"autoMemoryDirectory":…}'` at launch so CC's native auto-memory lands in the `memory/` submodule, ship both placements (A: repo-local via direnv, B: global), add a `SessionStart` guard that warns loudly when launched without the shim, and delete the dead `settings.local.json` `autoMemoryDirectory` writes that CC silently ignores (D10).

**Why now:** Plan 04 just shipped; the Step 6 verification surfaced the live-dir-vs-submodule divergence this fixes. The design (D10 + Memory Redirect Launcher, `docs/design.md:102-137`, `512-556`) is fully specified — code lags it. The current `write-settings.sh:21-29` and `session-start.sh:21-31` still write `autoMemoryDirectory` to `.claude/settings.local.json`, a tier CC discards; memory strands in `~/.claude/projects/<cwd>/memory/`.

**Tech stack:** POSIX `sh` (shim), Bash (orchestrators/hooks, `set -euo pipefail`), `jq`, `bats` tests, direnv (Placement A runtime dependency).

## File structure

| File | Change | Responsibility |
|------|--------|----------------|
| `scripts/install/launcher-shim` | **create** | Canonical shim body (POSIX sh). Single source of truth; copied verbatim by both placements. |
| `scripts/install/emit-launcher.sh` | **create** | Placement A: copy shim → `.gitlore/bin/claude`; idempotently ensure `.envrc` has `PATH_add .gitlore/bin`. |
| `scripts/install/global-shim.sh` | **create** | Placement B: copy shim → `${GITLORE_HOME:-$HOME/.gitlore}/bin/claude`; print (never write) the shell-rc `PATH` line. |
| `commands/install-launcher.md` | **create** | `/gitlore:install-launcher` — surfaces `global-shim.sh`. |
| `scripts/install/run.sh` | modify | Call `emit-launcher.sh`; stage `.gitlore/bin/claude` + `.envrc`; remind to `direnv allow`. |
| `scripts/install/write-settings.sh` | modify | Delete the dead `settings.local.json` `autoMemoryDirectory` write (keep the `.gitignore` defensive block). |
| `scripts/cc-hooks/session-start.sh` | modify | Delete the dead `settings.local.json` write; add the launcher guard; route own stdout so the guard JSON is the only thing on real stdout. |
| `commands/install.md` | modify | Mention the launcher + `direnv allow` in the summary. |
| `tests/launcher_shim.bats` | **create** | Shim behavior: passthrough vs inject vs 127. |
| `tests/emit_launcher.bats` | **create** | Placement A emitter. |
| `tests/global_shim.bats` | **create** | Placement B installer. |
| `tests/cc_hook_session_start.bats` | modify | Drop the `settings.local.json` assertion; assert the guard JSON. |
| `tests/install_run.bats` | modify | Assert `.gitlore/bin/claude` + `.envrc` are staged/executable. |
| `Makefile` | modify | Add the three new bats files to `test-unit`. |
| `docs/design.md`, `docs/plugin-readme.md` | modify | Changelog entry; flip the launcher from "unbuilt limitation" to shipped. |

## Steps

- [x] **1. Canonical shim asset.** Create `scripts/install/launcher-shim` verbatim from `docs/design.md:108-128`:

  ```sh
  #!/usr/bin/env sh
  # gitlore launcher shim. Injects --settings '{"autoMemoryDirectory":…}' so CC's
  # native auto-memory lands in the gitlore submodule. Identical in both placements;
  # see docs/design.md "Memory Redirect Launcher" (D10).

  # real claude = next `claude` on PATH after stripping my own dir
  self=$(cd "$(dirname "$0")" && pwd)
  newpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd:)
  real=$(PATH="$newpath" command -v claude) || { echo "gitlore: real claude not found" >&2; exit 127; }

  # already injected upstream? pass through (composability, anti-double-inject, anti-recursion)
  [ -n "$GITLORE_LAUNCHED" ] && exec "$real" "$@"

  # in a gitlore-enabled repo? cheap git checks first, so jq only runs for actual gitlore repos
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  mempath=$(git config --file "$root/.gitmodules" submodule.gitlore-memory.path 2>/dev/null)
  [ -n "$root" ] && [ -n "$mempath" ] || exec "$real" "$@"          # no gitlore submodule → passthrough
  [ "$(jq -r '.gitlore.enabled // false' "$root/.claude/settings.json" 2>/dev/null)" = true ] \
    || exec "$real" "$@"                                            # submodule present but disabled → passthrough

  json=$(jq -nc --arg p "$root/$mempath" '{autoMemoryDirectory:$p}')
  export GITLORE_LAUNCHED=1
  exec "$real" --settings "$json" "$@"
  ```

  `chmod 755 scripts/install/launcher-shim`. Commit: `feat: add canonical gitlore launcher shim (D10)`.

- [x] **2. Shim behavior tests (TDD red).** Create `tests/launcher_shim.bats`. The harness puts the shim in `shimdir` and a recording stub `claude` in `stubdir`, then invokes the shim by full path (so it strips `shimdir` from PATH and chains to the stub):

  ```bash
  #!/usr/bin/env bats

  load helpers/setup
  load helpers/fixtures

  SHIM_SRC="$PLUGIN_ROOT/scripts/install/launcher-shim"

  setup() {
    setup_tmp_repo
    SHIMDIR="$TMP_REPO/.shimdir"; STUBDIR="$TMP_REPO/.stubdir"
    mkdir -p "$SHIMDIR" "$STUBDIR"
    cp "$SHIM_SRC" "$SHIMDIR/claude"; chmod 755 "$SHIMDIR/claude"
    # Recording stub: prints its args so we can assert what the shim forwarded.
    printf '#!/bin/sh\necho "REAL:$*"\n' > "$STUBDIR/claude"; chmod 755 "$STUBDIR/claude"
    export PATH="$SHIMDIR:$STUBDIR:$PATH"
  }
  teardown() { teardown_tmp_repo; }

  @test "passthrough when not in a gitlore repo" {
    run "$SHIMDIR/claude" hello
    [ "$status" -eq 0 ]
    [ "$output" = "REAL:hello" ]
  }

  @test "passthrough when GITLORE_LAUNCHED already set (anti-double-inject)" {
    make_parent_with_memory
    mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
    GITLORE_LAUNCHED=1 run "$SHIMDIR/claude" hi
    [ "$output" = "REAL:hi" ]
  }

  @test "passthrough when submodule present but gitlore disabled" {
    make_parent_with_memory
    mkdir -p .claude; printf '{"gitlore":{"enabled":false}}\n' > .claude/settings.json
    run "$SHIMDIR/claude" hi
    [ "$output" = "REAL:hi" ]
  }

  @test "injects --settings autoMemoryDirectory in an enabled gitlore repo" {
    make_parent_with_memory
    mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
    run "$SHIMDIR/claude" hi
    [ "$status" -eq 0 ]
    [[ "$output" == *"--settings"* ]]
    [[ "$output" == *"autoMemoryDirectory"* ]]
    [[ "$output" == *"$TMP_REPO/memory"* ]]
    [[ "$output" == *"hi"* ]]
  }

  @test "exit 127 when no real claude is reachable" {
    # PATH = shim dir + a minimal toolbox (the utilities the shim needs) but no claude.
    tools="$TMP_REPO/.tools"; mkdir -p "$tools"
    for t in sh tr grep paste git jq dirname env; do ln -s "$(command -v "$t")" "$tools/$t"; done
    run env -i HOME="$HOME" PATH="$SHIMDIR:$tools" "$SHIMDIR/claude"
    [ "$status" -eq 127 ]
  }
  ```

  Run `bats tests/launcher_shim.bats` — all but the trivial passthrough cases fail until Step 1's shim is correct (it is), so this step mainly *locks in* behavior. Commit: `test: cover launcher shim passthrough/inject/127 paths`.

- [x] **3. Placement A emitter.** Create `scripts/install/emit-launcher.sh` (Bash, run from repo root):

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

  # Repo-local committed shim.
  mkdir -p .gitlore/bin
  cp "$PLUGIN_ROOT/scripts/install/launcher-shim" .gitlore/bin/claude
  chmod 755 .gitlore/bin/claude

  # direnv: prepend .gitlore/bin to PATH. Each PATH_add prepends, so the LAST one
  # wins the front slot — our line must land after any pre-existing PATH_add.
  line='PATH_add .gitlore/bin'
  if [ ! -f .envrc ]; then
    printf '%s\n' "$line" > .envrc
  elif ! grep -qxF "$line" .envrc; then
    last=$(grep -nE '^[[:space:]]*PATH_add( |$)' .envrc | tail -n1 | cut -d: -f1 || true)
    if [ -n "${last:-}" ]; then
      tmp=$(mktemp)
      awk -v n="$last" -v ins="$line" 'NR==n{print; print ins; next} {print}' .envrc > "$tmp"
      mv "$tmp" .envrc
    else
      printf '%s\n' "$line" >> .envrc
    fi
  fi
  ```

  Create `tests/emit_launcher.bats`:

  ```bash
  #!/usr/bin/env bats

  load helpers/setup

  EMIT="$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
  setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
  teardown() { teardown_tmp_repo; }

  @test "fresh repo: writes executable shim and .envrc PATH_add" {
    bash "$EMIT"
    [ -x .gitlore/bin/claude ]
    diff .gitlore/bin/claude "$PLUGIN_ROOT/scripts/install/launcher-shim"
    grep -qxF 'PATH_add .gitlore/bin' .envrc
  }

  @test "existing .envrc: inserts after the last pre-existing PATH_add" {
    printf 'PATH_add node_modules/.bin\nlayout python\n' > .envrc
    bash "$EMIT"
    # Our line is immediately after node_modules/.bin (so it wins the front slot).
    [ "$(grep -nxF 'PATH_add .gitlore/bin' .envrc | cut -d: -f1)" = "2" ]
    grep -qxF 'layout python' .envrc
  }

  @test "idempotent: re-run leaves a single PATH_add .gitlore/bin" {
    bash "$EMIT"; bash "$EMIT"
    [ "$(grep -cxF 'PATH_add .gitlore/bin' .envrc)" -eq 1 ]
  }
  ```

  Run `bats tests/emit_launcher.bats` → PASS. Commit: `feat: emit repo-local launcher shim + .envrc (Placement A)`.

- [x] **4. Wire Placement A into install; drop dead settings.local.json write.**

  In `scripts/install/run.sh`, after the `write-settings.sh` call (line 28) add:

  ```bash
  bash "$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
  ```

  Change the staging line (currently `git add .claude/settings.json .claude/gitlore-hook-setup .gitignore`) to also stage the launcher files:

  ```bash
  git add .claude/settings.json .claude/gitlore-hook-setup .gitignore .gitlore/bin/claude .envrc
  ```

  Update the final reminder (currently the two `echo … >&2` lines) to:

  ```bash
  echo "gitlore: install complete." >&2
  echo "Review the staged changes (.gitmodules, $mempath/, .claude/settings.json, .claude/gitlore-hook-setup, .gitignore, .gitlore/bin/claude, .envrc) and commit when ready." >&2
  echo "Then run 'direnv allow' so the launcher redirects memory into $mempath/ (no direnv? run /gitlore:install-launcher)." >&2
  ```

  In `scripts/install/write-settings.sh`, delete the dead `settings.local.json` write (lines 21-29: the `absmem=…` line through the if/else block). Keep the `.gitignore` block (lines 31-37) and the `git config gitlore.hooksDir` line. The file's remaining job: write `settings.json`, ensure `.gitignore`, set hooksDir.

  In `commands/install.md` step 4 "Summarize", add a bullet: "and remind them to run `direnv allow` (or `/gitlore:install-launcher` if they don't use direnv) so memory is redirected into the submodule."

  In `tests/install_run.bats`, extend the "install stages all artifacts" test (after the `.gitignore` assertion) with:

  ```bash
    [[ "$staged" == *".gitlore/bin/claude"* ]]
    [[ "$staged" == *".envrc"* ]]
    [ -x .gitlore/bin/claude ]
  ```

  Run `bats tests/install_run.bats` → PASS (no test asserted `settings.local.json`, so the removal is clean). Commit: `feat: wire launcher into install; drop dead settings.local.json write (D10)`.

- [x] **5. SessionStart launcher guard; drop dead settings.local.json write.**

  In `scripts/cc-hooks/session-start.sh`:

  (a) Delete the dead block (lines 21-31): the `absmem=…` line and the entire `# Update settings.local.json` if/else. Keep line 20 `mempath=$(gitlore_memory_path)` — it's used downstream.

  (b) Immediately after the two guards and `mempath=…` (i.e. before `git config gitlore.hooksDir …`), route the script's own stdout to stderr and reserve real stdout (fd 3) for the guard JSON only:

  ```bash
  # Keep stdout clean: everything below logs to stderr; only the guard JSON (if any)
  # goes to real stdout (fd 3), which CC parses for systemMessage/additionalContext.
  exec 3>&1 1>&2

  # Launcher guard (D10): without the shim, GITLORE_LAUNCHED is unset and CC's
  # native auto-memory strands in ~/.claude/projects/<cwd>/memory instead of the submodule.
  launcher_warning=""
  if [ -z "${GITLORE_LAUNCHED:-}" ]; then
    launcher_warning=$(jq -nc \
      --arg sys "gitlore: memory is NOT redirected — this session was started with a plain 'claude', so auto-memory will strand in the default directory, not the submodule. Fix: run 'direnv allow' in this repo (or '/gitlore:install-launcher' if you don't use direnv), then restart Claude Code." \
      --arg ctx "gitlore: GITLORE_LAUNCHED is unset — the launcher shim did not run, so CC auto-memory is writing to the default ~/.claude/projects/<cwd>/memory dir, NOT the gitlore submodule. Tell the user to run 'direnv allow' (Placement A) or '/gitlore:install-launcher' (Placement B) and restart. Do NOT write autoMemoryDirectory to any settings file — that tier is ignored (D10)." \
      '{systemMessage:$sys, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}')
  fi
  ```

  (c) At the very end of the script (after the ff-merge block), emit the guard JSON to fd 3:

  ```bash
  [ -n "$launcher_warning" ] && printf '%s\n' "$launcher_warning" >&3
  exec 3>&- 1>&2
  ```

  Note: the existing `exit 1` divergence/`live`-collision paths return before this — acceptable; on a hard error the warning is moot.

  In `tests/cc_hook_session_start.bats`:

  - The two no-op tests (`[ ! -f .claude/settings.local.json ]`) stay as-is.
  - Replace the test "writes autoMemoryDirectory and hooksDir and emits wrappers" with:

    ```bash
    @test "does not write settings.local.json (D10); sets hooksDir and emits wrappers" {
      make_parent_with_memory
      mkdir -p .claude
      printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
      run bash "$SESSION_START"
      [ "$status" -eq 0 ]
      [ ! -f .claude/settings.local.json ]
      [ "$(git config gitlore.hooksDir)" = "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks" ]
      [ -x .git/gitlore-pre-commit ]
      [ -x .git/gitlore-pre-push ]
    }

    @test "emits launcher-guard JSON on stdout when GITLORE_LAUNCHED is unset" {
      make_parent_with_memory
      mkdir -p .claude
      printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
      unset GITLORE_LAUNCHED
      run --separate-stderr bash "$SESSION_START"
      [ "$status" -eq 0 ]
      echo "$output" | jq -e '.systemMessage | test("direnv allow")'
      echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
      echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("GITLORE_LAUNCHED")'
    }

    @test "no launcher-guard JSON when GITLORE_LAUNCHED is set" {
      make_parent_with_memory
      mkdir -p .claude
      printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
      GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
      [ "$status" -eq 0 ]
      [ -z "$output" ]
    }
    ```

  Run `bats tests/cc_hook_session_start.bats` → PASS. Commit: `feat: SessionStart launcher guard; drop dead settings.local.json write (D10)`.

- [x] **6. Placement B: global shim + command.** Create `scripts/install/global-shim.sh`:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
  GITLORE_HOME="${GITLORE_HOME:-$HOME/.gitlore}"
  bindir="$GITLORE_HOME/bin"

  mkdir -p "$bindir"
  cp "$PLUGIN_ROOT/scripts/install/launcher-shim" "$bindir/claude"
  chmod 755 "$bindir/claude"

  case "$(basename "${SHELL:-sh}")" in
    fish) line="set -gx PATH $bindir \$PATH" ;;
    *)    line="export PATH=\"$bindir:\$PATH\"" ;;
  esac

  cat >&2 <<EOF
  gitlore launcher installed at $bindir/claude.
  Add this line to your shell rc to activate it (gitlore will not edit your rc):

      $line

  Then restart your shell. The shim auto-activates only in gitlore-enabled repos and no-ops everywhere else.
  EOF
  ```

  Create `commands/install-launcher.md`:

  ```markdown
  ---
  description: Install the gitlore launcher globally (no-direnv fallback)
  allowed-tools: ["Bash"]
  ---

  # /gitlore:install-launcher

  One-time, machine-level setup of the gitlore launcher for users who don't use direnv, or who launch Claude Code from outside an allowed directory. Placement A (`/gitlore:install` + `direnv allow`) is preferred; this is the fallback.

  1. Run:
     ```bash
     "${CLAUDE_PLUGIN_ROOT}/scripts/install/global-shim.sh"
     ```
  2. Relay the printed `PATH` instruction to the user **verbatim**. Tell them to add that line to their shell rc and restart their shell. Do not edit their rc yourself.
  ```

  Create `tests/global_shim.bats`:

  ```bash
  #!/usr/bin/env bats

  load helpers/setup

  GLOBAL="$PLUGIN_ROOT/scripts/install/global-shim.sh"
  setup() {
    setup_tmp_repo
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
    export GITLORE_HOME="$TMP_REPO/.gitlore-home"
  }
  teardown() { teardown_tmp_repo; }

  @test "writes an executable global shim matching the source" {
    SHELL=/bin/bash bash "$GLOBAL"
    [ -x "$GITLORE_HOME/bin/claude" ]
    diff "$GITLORE_HOME/bin/claude" "$PLUGIN_ROOT/scripts/install/launcher-shim"
  }

  @test "prints a bash/zsh export PATH instruction (not auto-edited)" {
    run --separate-stderr env SHELL=/bin/zsh bash "$GLOBAL"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"export PATH=\"$GITLORE_HOME/bin:\$PATH\""* ]]
  }

  @test "prints a fish set -gx PATH instruction" {
    run --separate-stderr env SHELL=/usr/bin/fish bash "$GLOBAL"
    [[ "$stderr" == *"set -gx PATH $GITLORE_HOME/bin \$PATH"* ]]
  }

  @test "idempotent: re-run leaves a single executable shim" {
    SHELL=/bin/bash bash "$GLOBAL"; SHELL=/bin/bash bash "$GLOBAL"
    [ -x "$GITLORE_HOME/bin/claude" ]
  }
  ```

  Run `bats tests/global_shim.bats` → PASS. Commit: `feat: global launcher shim + /gitlore:install-launcher (Placement B)`.

- [x] **7. Register new test files; full suite green.** In `Makefile`, append to the `test-unit` recipe's file list: `tests/launcher_shim.bats tests/emit_launcher.bats tests/global_shim.bats`. Run `make test` → all PASS. Commit: `test: register launcher test files in Makefile`.

- [ ] **8. Docs.**
  - `docs/plugin-readme.md`: replace the known-limitation note about the "unbuilt redirect launcher" with the shipped flow — after `/gitlore:install`, run `direnv allow` (or `/gitlore:install-launcher` without direnv); memory then redirects into the submodule. Update the status table row accordingly.
  - `docs/design.md`: add a Decisions Log / changelog row dated 2026-05-24: "Plan 05 built the Memory Redirect Launcher (shim + Placement A direnv + Placement B global + SessionStart guard) and removed the dead `settings.local.json` `autoMemoryDirectory` writes from `write-settings.sh`/`session-start.sh` (the tier CC ignores — D10)."
  - Mark Steps 1-7 `[x]` in this plan as they land.

  Commit: `docs: launcher shipped — update plugin-readme + design changelog`.

- [x] **9. Dogfood in this repo (the real target).** Per "dogfood early": this repo is the production target and currently suffers the live-dir-vs-submodule divergence.
  1. `CLAUDE_PLUGIN_ROOT=$PWD bash scripts/install/emit-launcher.sh` → confirm `.gitlore/bin/claude` + `.envrc` `PATH_add` line.
  2. `direnv allow`, then start a fresh Claude Code session in this repo (under `--plugin-dir`, per the stale-cache lesson in `reference_plugin_cache_staleness`).
  3. In the new session confirm `echo $GITLORE_LAUNCHED` = `1` and that the `SessionStart` guard did **not** fire (no warning).
  4. Confirm CC's auto-memory now resolves to `<repo>/memory` (write a throwaway memory, verify it lands in the submodule worktree, then discard).
  5. Record findings in this plan; fix any in-plan. Then `git add .gitlore/bin/claude .envrc` and commit if adopting the launcher for this repo. Commit: `chore: adopt gitlore launcher in this repo (dogfood)`.

  **Findings (2026-05-25):** Dogfood passed cleanly, no in-plan fixes needed.
  - `emit-launcher.sh` wrote `.gitlore/bin/claude` (executable, byte-identical to `scripts/install/launcher-shim`) and added `PATH_add .gitlore/bin` to a fresh `.envrc`.
  - After `direnv allow` + fresh session: `echo $GITLORE_LAUNCHED` → `1`; the launcher shim ran.
  - The `SessionStart` launcher guard did **not** fire (no warning emitted) — correct, since `GITLORE_LAUNCHED` was set.
  - CC auto-memory location validated against the open submodule `memory/` directory.
  - Adopted: `.gitlore/bin/claude` + `.envrc` committed for this repo.

## Scope

- **In:** the canonical shim; Placement A (direnv) + Placement B (global) + `/gitlore:install-launcher`; the `SessionStart` launcher guard; removal of the dead `settings.local.json` `autoMemoryDirectory` writes; tests; docs; self-dogfood.
- **Out:** `WorktreeCreate`/`WorktreeRemove` hooks (next plan); auto-editing the user's shell rc (Placement B prints only); pinning a specific `claude` version (shim chains to the next `claude` — CC's own version selector); migrating existing stranded memory out of the default dir (orthogonal one-off).

## Open decisions during execution

- **`.envrc` insertion vs front-most slot.** Design says insert after the *last* existing `PATH_add` so gitlore wins the front. Step 3 implements exactly that; the Step 3 test asserts position. If a project uses a non-`PATH_add` PATH mutation after the last `PATH_add`, gitlore may not be front-most — out of scope; note it if it surfaces in dogfood.
- **Guard on every unlaunched session.** The guard fires on *every* `SessionStart` without the shim, including legitimate plain-`claude` use during install (before `direnv allow`). That's intended (loud until fixed), but confirm it isn't annoying in the dogfood; if it is, consider gating it on "launcher files exist but weren't used."
