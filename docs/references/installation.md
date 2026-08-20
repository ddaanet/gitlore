# Installation and launch mechanism

The literal setup detail `design.md`'s Architecture points at — the install command's own steps, the launcher shim and its two placements, the hook wrapper files, per-hook-manager wiring syntax, what every `SessionStart` does, and memory remote creation — followed by the decisions that argue for that shape (D5, D10, D11, D14, D21, D25). Motivation and conclusions stay in `design.md`; this file is what you need while installing or debugging an install, or while proposing a change to how any of it is wired.

---

## The Install Command

`/gitlore:install` — one-time setup, idempotent.

Precondition: must run from the **main worktree** (repo root). In a linked worktree the memory submodule is typically unchecked-out, so submodule git ops would silently escape to the parent repo — staging the parent's HEAD as the memory gitlink and creating branches in the parent. `run.sh` aborts when the per-worktree git dir differs from the common git dir. As a second line of defense, `init-submodule.sh` refuses to stage the gitlink when the memory path has no `.git` (registered but not checked out).

1. Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; if unset, warn and offer to enable it (required for sub-agent-based resolve).
2. Prompt for memory path (default: `memory`). If the path exists with unrelated content, refuse and prompt for an alternative.
3. Prompt for the project pre-commit command (stored as `gitlore.precommitCommand`).
4. Display install-time disclosure: proposed memory remote name, owner, visibility (inherited from parent), and notice that memory may contain session context. Await acknowledgement (informational, not a hard gate).
5. Create the memory remote with explicit D8 confirmation — see Remote Repository below. `gh repo create` (or provider-appropriate method) runs. If the parent has no remote, skip; memory stays local-only.
6. `git submodule add <remote-url> <path>` (or a local path if no remote) — registers the submodule in `.gitmodules` and initializes the empty working tree.
7. Seed memory content inside the submodule worktree:
   - If existing auto-memory exists at `~/.claude/projects/<hash>/memory/`, copy it in.
   - Otherwise, scaffold a `MEMORY.md` index file.
8. `git -C <memory-path> add -A && git -C <memory-path> commit -m "Initial memory"` — non-empty initial commit; install is git-atomic.
9. Create the `live` branch at the initial commit and check the worktree out detached at it (the branch model — `live` is never checked out as a branch).
10. If a remote was created, `git -C <memory-path> push origin live` so the parent's submodule pointer is reachable upstream.
11. Write `gitlore.enabled: true` and `gitlore.precommitCommand` to `.claude/settings.json`.
12. Emit the memory redirect launcher — `.gitlore/bin/claude` plus the `.envrc` `PATH_add` line, both staged for commit — then activate it: `direnv allow` when direnv is available (non-fatal; a read-only direnv dir is not a blocker), otherwise `global-shim.sh`. Does **not** write `autoMemoryDirectory` to any settings file; that tier is ignored (D10).
13. Write `gitlore.hooksDir` (abs path to plugin hooks) to local git config.
14. Run hook-manager detection script → apply idempotent wiring, write sentinel file.
15. Leave tracked changes staged for the user to commit.

Idempotency rules for re-runs: existing submodule → verify and skip creation; existing settings keys → overwrite only if value differs; migration → detect prior migration (by presence of migrated files or a done-marker) and skip; existing hook-manager wiring with our marker → skip; existing remote → skip creation. A partial install (user aborted mid-flow) is recovered by re-running.

## Memory Redirect Launcher

Claude Code's native auto-memory writes to `~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set in an honored settings tier. Project settings are *not* honored (D10), so the only per-project, non-global mechanism is the `--settings` flag at launch. The launcher is a thin `claude` shim that injects it transparently — the user keeps typing `claude`, and memory lands in the submodule.

**One shim, two placements.** The shim body is identical in both modes; only how it lands on `PATH` differs. It is `#!/usr/bin/env sh`:

```sh
#!/usr/bin/env sh
# real claude = next `claude` on PATH after stripping my own dir
self=$(cd "$(dirname "$0")" && pwd)
newpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd:)
real=$(PATH="$newpath" command -v claude) || { echo "gitlore: real claude not found" >&2; exit 127; }

# already injected upstream? pass through (composability, anti-double-inject, anti-recursion)
[ -n "$GITLORE_LAUNCHED" ] && exec "$real" "$@"

# opt-in: load the plugin from the checkout you're standing in, not the marketplace cache
if [ -n "$GITLORE_AUTO_CLAUDE_PLUGIN_DIR" ] && [ -f .claude-plugin/plugin.json ]; then
  set -- --plugin-dir . "$@"
fi

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

- **Real-claude resolution.** The shim strips its own directory from `PATH`, then takes the next `claude`. That next entry is normally Claude Code's own version-selector launcher (`~/.local/bin/claude`), so version selection is preserved — the shim chains to it rather than pinning a version.
- **`GITLORE_LAUNCHED` sentinel.** Set before exec. Does triple duty: (a) when both shims are on `PATH`, the repo-local one runs first, execs the global one which sees the sentinel and passes through — no double injection; (b) guards against any accidental recursion; (c) lets `SessionStart` detect a plain `claude` launch (sentinel unset) and warn loudly instead of silently stranding memory.
- **`GITLORE_AUTO_CLAUDE_PLUGIN_DIR` (opt-in, default off).** When the var is non-empty *and* the cwd holds a `.claude-plugin/plugin.json`, the shim prepends `--plugin-dir .`, so Claude Code loads the plugin from the checkout you are standing in rather than the marketplace cache — which lags the repo at the same version string, making plugin changes untestable without a reinstall. Default-off because silently shadowing an installed plugin whenever a user cd's into its source tree would mask a released version with dirty working-tree code; opting in is a one-line rc export. Injected via `set -- --plugin-dir . "$@"` before the repo checks, so it applies on every exec path including passthrough — a plugin checkout need not be a gitlore repo. The `GITLORE_LAUNCHED` sentinel still short-circuits first, so an upstream shim's decision wins.
- **Path built with `jq`.** Handles spaces/quoting safely; computed at runtime so committed shims stay portable across clones. `--settings` loads an *additional* settings tier (`flagSettings`), so only `autoMemoryDirectory` is overridden; all other settings still resolve from their normal tiers.

**Placement A — repo-local, direnv (default).** `/gitlore:install` emits two **committed** files: `.gitlore/bin/claude` (the shim) and `.envrc`. The `.envrc` puts `.gitlore/bin` at the **front** of `$PATH` so the shim shadows the real `claude`, which is what direnv's `PATH_add .gitlore/bin` does. A fresh `.envrc` gets `source_up_if_exists` as its first line so parent-directory configs are inherited. With an existing `.envrc`, direnv evaluates top-to-bottom and each `PATH_add` prepends, so the *last* one wins the front slot — gitlore's line is inserted after any pre-existing `PATH_add` (idempotent no-op if already present). After a one-time `direnv allow` the shim is on `PATH` inside the repo tree only, subdirectories included, and both files travel with the repo. The path is namespaced under `.gitlore/bin/` to avoid colliding with a project's own `bin/`.

**Placement B — global shim, no-direnv fallback (automatic).** When direnv is not found during install, `run.sh` runs `scripts/install/global-shim.sh`, which drops the *same shim* at `~/.gitlore/bin/claude` and **prints** (does not auto-append) the one `PATH` line for the user's shell rc (e.g. `set -gx PATH ~/.gitlore/bin $PATH` for fish). Per-repo installs never touch it otherwise. The gitlore-repo detection is generic, so this one shim auto-activates in any gitlore repo and no-ops everywhere else. It covers users without direnv, and launches from outside an allowed directory.

## Hook Wrappers

`SessionStart` writes two flat files into the repo's **git common dir** on every startup, resolved via `git rev-parse --git-common-dir`:

- `<common-dir>/gitlore-pre-commit`
- `<common-dir>/gitlore-pre-push`

The common dir is shared across all worktrees (`--git-common-dir` → `.git` in the main worktree, `<main>/.git` in a linked one), so one emission is reachable and executable from every worktree — including one where no Claude session has ever run. Every producer (`emit-wrappers`) and every consumer (the wired stubs and manager configs) resolves the wrapper through `--git-common-dir`; none hardcode `.git/`, which is a gitlink *file* in a linked worktree. See D11.

Each wrapper delegates to the current plugin via `git config gitlore.hooksDir` (regular git config, shared across worktrees via the common config). Stable paths for hook manager configs; plugin updates are transparent. If `gitlore.hooksDir` is unset (a plain `git commit` outside any Claude session before SessionStart has fired), the wrapper exits 0 after emitting a stderr hint — `"gitlore skipped: hooks not installed"` plus instructions to install the marketplace, plugin, and start Claude.

```sh
#!/bin/sh
HOOKS_DIR=$(git config gitlore.hooksDir)
if [ -z "$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "$HOOKS_DIR/pre-commit" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Relaunch Claude Code in this repo with 'claude -c' to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "$HOOKS_DIR/pre-commit" "$@"
```

## Hook Manager Support

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook setup command or keyword (`lefthook install`, `npx husky`, `overcommit --install`, `direct`, or `manual`). `SessionStart` replays it to re-wire hook-manager integration on a clone or a new machine.

The detection script outputs structured results. Each hook manager has an idempotent wiring step (uses marker comment `# gitlore: managed` to detect and skip duplicates) and a sentinel command stored in `.claude/gitlore-hook-setup` and replayed by SessionStart on clone or plugin reinstall.

**Detection precedence** (first match wins; multiple detections produce a warning listing all found managers):

1. `.lefthook.yml` or `lefthook.yml` → Lefthook
2. `.husky/` directory → Husky (v7+)
3. `.overcommit.yml` or `.git/hooks/overcommit-hook` → Overcommit
4. Otherwise → None (direct)

The `direct` case is the default whenever no recognized manager is present — whether the repo has a hand-rolled `.git/hooks/pre-commit` (the direct installer appends, coexisting) or no hooks at all. The shared `.git/hooks` dir exists in every git repo, so direct wiring always works, and defaulting bare repos to it makes the double-commit guarantee (FR8) active out of the box rather than waiting on a manual copy-paste step. `manual` is **not auto-detected**: it stays a valid sentinel a user can set by hand, and is emitted for the ambiguous multi-manager case.

**Wiring** is applied symmetrically for `pre-commit` and `pre-push`. Every manager reaches the wrapper through `$(git rev-parse --git-common-dir)/gitlore-<hook>` rather than a literal path (D11), so what differs per manager is only how that command is spelled and whether a shell expands it.

*Lefthook* (`lefthook install`) — a `gitlore` command under `pre-commit` and `pre-push` in `lefthook.yml`, `run: '$(git rev-parse --git-common-dir)/gitlore-pre-commit'`. Lefthook runs `run` through a shell, so the substitution expands at hook time.

*Husky* (`npx husky`) — a guarded `exec "$(git rev-parse --git-common-dir)/gitlore-<hook>" "$@"` appended to `.husky/pre-commit` and `.husky/pre-push`, created if missing. Husky runs the script via `sh`, so the substitution expands.

*Overcommit* (`overcommit --install`) — a custom `gitlore` hook under `PreCommit` and `PrePush` in `.overcommit.yml`. Overcommit's `command:` is an array exec'd **directly, with no shell**, so the wrapper has to be reached through an explicit one: `command: ['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"','gitlore']` — the trailing `'gitlore'` sets `$0`, and overcommit appends the applicable files as `$@`.

*None, i.e. direct* (sentinel `direct`, a keyword SessionStart interprets rather than runs) — shell stubs at `git rev-parse --git-path hooks/<hook>` that exec the wrapper. The hooks path is resolved with `--git-path`, not a literal `.git/hooks/…`, so the `[ -f ]` test and the `cat >` survive a sentinel replay in a linked worktree.

*Multiple managers, or a hand-set sentinel* (`manual`, also a keyword) — print a copy-paste snippet and modify nothing. Reached only when detection is ambiguous or a user sets the sentinel themselves.

**Sentinel handling in SessionStart:**

- `direct` → re-run the direct-wiring installer.
- `manual` → emit `systemWarning` reminding the user to verify wiring.
- Any other value → run as a shell command in the repo root.

Idempotency: every wiring modification uses a detection marker (`# gitlore: managed` or the format-appropriate equivalent). Re-applying is a no-op.

## The Session

Everything install wires is re-pinned, re-emitted or replayed at the start of every session, which is what makes a clone, a new machine and a plugin upgrade heal themselves.

**`SessionStart`.** Guards: if `gitlore.enabled` is not `true`, or `.gitmodules` has no `gitlore-memory` entry, no-op.

1. **Launcher guard.** If `GITLORE_LAUNCHED` is unset, the session was started with a plain `claude` — memory is *not* redirected and will strand in the default directory. Say so on `systemMessage`, naming the fix (`direnv allow`, or the global shim on a machine without direnv). Nothing is written to any settings file; that tier is ignored (D10).
2. **Re-pin the five plugin-path keys** — `gitlore.hooksDir`, `gitlore.commitCommand`, `gitlore.pushCommand`, `gitlore.mergeCommand`, `gitlore.memoryApprovalClauseFile` — so a plugin upgrade heals itself.
3. **Emit the wrappers** `gitlore-pre-commit` and `gitlore-pre-push` into the git common dir, and the FR11 commit gate into the memory store and each tier. Idempotent and worktree-agnostic (D11, D12).
4. **Replay the hook-manager sentinel** to reinstate wiring after a clone or a new machine (`direct` and `manual` are keywords, not commands — see Hook Manager Support above).
5. **Materialize the store.** Initialize the submodule if needed; add a memory worktree for a linked parent worktree; create local `live` from `origin/live` (or from the checked-out gitlink when there is no remote) after a clone without `--recurse-submodules`, since the branch model references `live` as a local ref.
6. **Detach at `live` and fast-forward**, or skip the fast-forward with a notice when memory is dirty. A fast-forward that fails is divergence: report it and route to `/gitlore:resolve`.
7. **Propagate the tiers.** For each mounted tier: initialize, fetch its remote `live` fast-forward-only, and re-detach at `live`. A diverged, unfetchable or mid-merge tier is reported by name and left untouched — never silently skipped, because a tier that stops propagating looks exactly like one with nothing to say.
8. **Compose the indexes**, then run the dangling-pointer report (D34). A refusal writes nothing and says why; a partial write says which indexes are composed.
9. **Emit the standing orientation** on `additionalContext`: the FR11 prohibition (D12) and the active tiers' own routing descriptions (D28).

**Worktree creation — handled by `SessionStart`, not a `WorktreeCreate` hook.** Memory-worktree setup for a new worktree happens lazily at the next `SessionStart` in that worktree (`git -C <main-repo>/.git/modules/gitlore-memory worktree add --detach <worktree-path>/<memory-rel-path> live`). This is uniform across every way a worktree comes into being:

- **`claude --worktree <name>`** — starts a *new session* in the new worktree, so `SessionStart` fires there with `cwd` = the worktree path (verified, CC 2.1.150).
- **Manual `git worktree add`** — next `SessionStart` in that worktree handles it.
- **Claude Desktop's worktree button** — does not fire `WorktreeCreate` at all (CC #57209), but a session still starts there, so `SessionStart` covers it.

Lazy creation is correct: with no session there is no auto-memory being written, so there is nothing to set up until the first session needs it.

The wrapper paths being gitlink-aware (D11) is what makes this *reachable* in a linked worktree: a literal `.git/gitlore-*` aborts `emit-wrappers` under `set -e` before step 5 runs, and blocks committing in the worktree outright.

> **Why not a `WorktreeCreate` hook.** Verified against CC 2.1.150 (`claude-code-guide`, 2026-05-25): `WorktreeCreate` is an **override** hook — it fires *before* the worktree exists, the script is expected to *create* it and print only its absolute path on stdout, and any extra stdout makes CC hang (#27467). Its stdin carries `{hook_event_name, cwd, name}` — **no** worktree path and **no** branch (CC defaults the branch to `worktree-<name>`); `hookSpecificOutput.worktreePath` is an HTTP-hooks-only *output* field. It also does not fire for Desktop-created worktrees, and there is no post-creation hook (#27744). Registering it would mean hijacking worktree placement for zero benefit over the `SessionStart` path.

**`WorktreeRemove`** (advisory — cannot block). Input provides `worktree_path` only (verified CC 2.1.150 — no branch field). A non-zero exit logs a warning but cannot stop the removal. Guard: no-op if `.gitmodules` has no `gitlore-memory` entry.

1. Derive the memory submodule worktree path as `<worktree_path>/<memory-rel-path>`. If it is not a registered memory worktree (e.g. no session ever ran there, or an ephemeral subagent worktree), no-op. Otherwise `git -C <memory-gitdir> worktree remove <memory-submodule-worktree-path>` (prune if the directory is already gone). On failure (locked, uncommitted changes), emit a warning; never block parent worktree removal.
2. Nothing else is removed. CC leaves the parent branch in place on worktree removal (verified 2.1.150, #28422, #38287), and memory carries no named branch of its own; `live` is shared and survives. Gitlore never touches parent branches.

**`PostToolBatch` — the plugin-upgrade notice.** `plugin-upgrade-batch.sh` compares the plugin root this session froze at against what the install record says is installed for this repo, and reports a mid-session upgrade once per episode. It reports and never repairs; see D21.

**`SessionStart` and `PreCompact` — the nudge reset.** `nudge-reset.sh` re-arms the once-per-episode notices (index byte budget, plugin upgrade). Both markers claim "this session has already been told", and both events end the context that claim rests on; see D21.

**`PostToolUse(EnterWorktree|ExitWorktree)` — the drift guard.** `worktree-drift.sh` warns when an in-process worktree switch has moved the session's cwd away from the repo whose memory is redirected. See D15.

## Remote Repository

The memory submodule is pushed to a dedicated remote, matching the parent repo's provider, ownership, and visibility where possible.

**Naming**

- Default: `<parent-remote-name>-memory`, derived from `origin` on the parent (e.g., `github.com/org/project.git` → `project-memory`).
- If a repo with the default name exists in the target namespace, prompt for an alternative.

**Ownership**

- Default: same owner as parent `origin` (user account or org).
- Overridable at creation time.

**Visibility**

- Default: match parent repo (public parent → public memory; private parent → private).
- Rationale: memory is auxiliary to the project; no reason to split access control.
- User can override the default.

**Install-time disclosure (informational)**

Before creating the remote, display proposed name, owner, and visibility (inherited from parent), along with:

> Memory pushed to this remote may contain any context Claude has recorded — project details, decisions, or incidental session content. Each memory commit is reviewed and confirmed before it's pushed, so you control what goes up.

This is orientation, not a clearance gate. The effective gate is the per-commit review (FR 11).

**Creation method**

1. **GitHub + `gh` CLI available** → `gh repo create <owner>/<name> [--public|--private]` matching parent visibility.
2. **Other providers** → emit copy-paste instructions: "Create a repository at `<detected-provider>` named `<name>` with matching visibility, then paste the clone URL here." Wait for URL.
3. **Parent has no remote** → skip memory remote creation. Memory stays local-only. Informational message; user can add a remote later.

**On creation failure** (auth, quota, network, name collision): fall back to method 2 (copy-paste). Do not abort install.

**Push semantics**

Per NFR5 (double-commit semantics): memory `live` is pushed before parent push on every `git push`. Parent remote always points at a submodule SHA reachable on the memory remote.

## Decisions — D5, D10, D11, D14, D21, D25

Why the wiring above has this shape: where the wrappers live and how they are anchored, why the redirect is a launch-time shim, what SessionStart says to whom, and the two refusals — direct wiring after an existing `exec`, and a mid-session plugin upgrade.

**D5 — Wrapper scripts in the git common dir, not tracked**

Tracking hook scripts in the repo would cause commit churn on every plugin update and couple the repo's history to the plugin's versioning. Storing flat wrappers in the git common dir (`<common-dir>/gitlore-pre-commit`, `<common-dir>/gitlore-pre-push`, resolved via `git rev-parse --git-common-dir`) keeps them untracked and local. `SessionStart` regenerates them on every startup, so they always reflect the current plugin version. The common dir (rather than a literal `.git/`) is what makes the wrappers reachable from linked worktrees, where `.git` is a gitlink file — see Hook wrappers above and **D11**.

Wrappers exec the real hook scripts via `$(git config gitlore.hooksDir)/<hook>`. The wrapper degrades to a clean skip (exit 0 + stderr hint) in **two** cases, not one:

1. **`gitlore.hooksDir` unset** — a plain `git commit` outside any Claude session before SessionStart has fired. Hint: install the marketplace, plugin, and start Claude.
2. **`gitlore.hooksDir` set but `$HOOKS_DIR/<hook>` does not exist** — the version-pinned config points at a plugin-cache dir that was GC'd after a plugin upgrade, in the window before the next SessionStart re-pins it. Without this guard the wrapper `exec`s a missing path and the commit/push **hard-fails** with `exec: …: not found`. Hint: relaunch with `claude -c`.

Both keep git operations unblocked rather than breaking a commit on a transient/stale-config condition.

**The refresh is `claude -c`, not a cold session.** Any process start re-pins the five keys — `SessionStart` fires on a resume as it does on a startup, with `source=resume` (D21) — so a resume closes the staleness window while keeping the conversation that hit it. A cold session closes the same window and throws the context away. This is the same remedy the upgrade notice names, for the same reason: what went stale was frozen at process start, and only a new process re-reads it.

**D10 — Memory redirect via a launch-time `--settings` shim, not project settings**

Claude Code resolves `autoMemoryDirectory` only from the `policySettings`, `flagSettings`, and `userSettings` tiers (verified by reading the resolver in the CC binary, v2.1.150). Project-level `.claude/settings.json` and `.claude/settings.local.json` are deliberately excluded for security — a checked-in repo setting must not be able to redirect where a user's memory is written. The discard is silent: a project tier carrying the key produces no diagnostic, and memory simply lands in the default `~/.claude/projects/<sanitized-cwd>/memory/` dir (Rejected Alternatives).

The honored tiers are either global (`userSettings`, `policySettings`) or per-launch (`flagSettings`, via `--settings`). Per-project redirection without polluting other projects therefore requires supplying the value at launch. A thin `claude` shim injects `--settings '{"autoMemoryDirectory":…}'` transparently (see Memory Redirect Launcher). This keeps the value proposition intact — the user invokes Claude Code normally and uses its *native* auto-memory; only the storage directory is redirected, with no cowork semantics.

Because an unredirected launch strands memory silently, the `SessionStart` launcher guard (sentinel `GITLORE_LAUNCHED`) detects one and warns.

**D11 — Gitlink-aware wrapper paths (common-dir anchor) for linked-worktree support**

A literal relative `.git/gitlore-<hook>` in the wrapper writer (`emit-wrappers`) and in the hook-manager consumers works only where `.git` is a directory — the main worktree. In a linked worktree `.git` is a gitlink *file*, so the path fails on both sides: `cat > .git/gitlore-*` aborts SessionStart under `set -e`, and the shared wired hook (which lives in the common dir and therefore fires in *every* worktree) `exec`s the literal path and **blocks the commit** (`exec: … not found`). Both verified empirically against git 2.47.3.

The wrapper is therefore anchored at `$(git rev-parse --git-common-dir)/gitlore-<hook>` on both the write and exec sides, across all managers (direct, husky, lefthook, overcommit, manual). The common dir is shared, so one emission covers every worktree, including a session-less linked worktree (plain `git worktree add` + `git commit`).

Considered and rejected: a **per-worktree** anchor via `git rev-parse --git-path gitlore-<hook>` (which resolves to `…/worktrees/<name>/gitlore-<hook>`). It reintroduces the commit-blocking gap in any worktree where no session has run yet, because the shared wired stub would `exec` a per-worktree wrapper that does not exist. The common-dir anchor has no such gap. (The commit-message file legitimately uses the per-worktree `--git-path` because each worktree has its own pending message; the wrapper is the opposite — one shared executable.)

Corollary fix: once the wrapper *fires* in a linked worktree, the git-hook runs `git -C "$mempath" …` under `set -e`. If the memory submodule worktree was never created there (session-less worktree), this would abort and block the commit for a *new* reason. Both `pre-commit` and `pre-push` therefore guard with an early `[ -e "$mempath/.git" ] || exit 0` — nothing to sync, never block.

**D14 — User-facing SessionStart output on `systemMessage`**

The Claude Code hook output channels (characterized 2026-06-10): `systemMessage` (top-level JSON field) is the only reliably user-visible channel; `hookSpecificOutput.additionalContext` is injected into the model's context but **never echoed to the user**; stdout is consumed as JSON and not echoed; stderr is shown to the user only on exit code **2** (or any non-zero under `--verbose`). SessionStart is non-blocking — the session continues regardless of exit code.

A notice on stderr is therefore effectively invisible, and a silent success path leaves the user with no confirmation that memory is wired at all. Routing notices through the agent (`additionalContext` "tell the user…") is rejected: it puts the model on the hot path against NFR1/D7.

Every user-facing SessionStart notice rides `systemMessage`, accumulated into the single SessionStart JSON the hook writes to fd 3:

- **Divergence** error → `systemMessage` + `exit 0`. Exit 0 because stdout JSON is parsed only on exit 0, so a non-zero exit would discard the very message it was meant to signal, and because SessionStart's exit code is non-blocking and consumed by nothing. The script still halts there, before the tier propagation pass.
- **Dirty-skip** notice → `systemMessage`, informational.
- **Clean success** → a brief confirmation (`memory ready (detached at live)`), per the chosen always-confirm behaviour.
- **Launcher-not-redirected** warning → `systemMessage`; when present it leads the message and the state line follows.

`additionalContext` carries the standing commit-protocol orientation (D12) on every path. The agent-vs-user text branch (`gitlore_say_for_agent_or_user`) exists only for the git hooks (`pre-commit` / `pre-push` / `memory-pre-commit`), which run outside a session where `CLAUDECODE` may be unset; SessionStart always runs in-session, so its notices are written directly for the user.

**D21 — A mid-session plugin upgrade is a notice, not a self-healing config**

`CLAUDE_PLUGIN_ROOT` is resolved once, at process start, from `~/.claude/plugins/installed_plugins.json`. That record keeps moving while a session runs: another repo's session installs, or the user runs `/plugin update`. Everything this session froze at start then belongs to the *old* version — hook event registration, skill bodies, agent definitions, and the five `gitlore.*` keys that point into the plugin root (D5). The `PostToolBatch` hook `plugin-upgrade-batch.sh` notices the disagreement and names the remedy, once per episode.

**Everything frozen at process start is re-read on a resume, so `claude -c` is the entire remedy.** Verified 2026-07-31 by a two-run `--plugin-dir` probe whose `SessionStart` hook logged its root and the payload's `source`, with `hooks.json` rewritten between runs: the second run fired `SessionStart` with `source=resume` and ran the **new** command, under the **same** `session_id`. The transcript records no plugin path or version, so a resumed process has no stale root to restore — it re-resolves the root from the install record, re-pins the five keys, re-emits the wrappers and re-wires the memory gate exactly as a cold start does, and the conversation survives. Nothing available inside a live session substitutes for it.

**Why reporting is the whole fix.** Both ways of making a live session adopt the upgrade produce a *split-version* session, strictly worse than uniform staleness: the git-config keys would point into the new version while CC-side hook registration, skill bodies and agent definitions stayed on the old one. Uniform staleness has one failure mode and one remedy; a split has neither.

**Detection.** The hook compares the frozen root against the entries the record holds for this plugin — the user-scoped one, plus any entry pinned to this project — and fires only when that set is non-empty and holds no entry equal to the frozen root. A repo deliberately pinned behind the user-scoped version is therefore silent, which is the point: installs are pinned per scope, not globally, and repos routinely sit at different versions. The family is identified by the frozen root's parent directory rather than a `gitlore@ddaanet` literal, so a fork or a renamed marketplace works unchanged. Three guards precede it: no `CLAUDE_PLUGIN_ROOT`, no `gitlore-memory` submodule, and a frozen root outside the plugin cache — the last because a `--plugin-dir` checkout is never stale, and its parent is an ordinary source directory whose neighbours the record may name for some *other* locally-installed plugin. There is no `grep -F` short-circuit ahead of the record query: the frozen root can appear in the record under a different `projectPath`, where a bare match would read as "installed here" and suppress a real notice.

**Both channels, and the user-facing one carries the instruction.** D14's house style keeps `systemMessage` curt and free of actionable phrases, leaving remedies to `additionalContext`. This is the deliberate exception, on D7 grounds: only the user can exit and relaunch, and a hot-path notice routed through the agent is model-dependent. So the user's line names the remedy directly. The agent's line is mostly a prohibition — `/plugin`, `/reload-plugins` and rewriting the `gitlore.*` keys are all dead ends, none of them re-fires `SessionStart`.

**Once per episode, re-armed by a compaction.** A marker in the memory store's gitdir, keyed by session and swept after seven days, mirrors the index byte-budget nudge; `nudge-reset.sh` clears both at `SessionStart` and `PreCompact`. A compaction re-arms the notice deliberately: what survives is a summary, and the session is still running the old root.

**D25 — Direct wiring refuses rather than appends after an existing `exec`**

`wire-direct.sh` appends its managed block to an existing `.git/hooks/<hook>` file. `exec` replaces the process, so a pre-existing hook body that already ends in `exec …` (e.g. `exec just precommit`) makes the appended gitlore block unreachable dead code — the commit/push succeeds, the project's own gate runs, and gitlore's sync silently never fires. No warning at install time or commit time.

Detection is a heuristic, not a shell parse: any non-comment line whose first token is `exec`. A false positive (an `exec` inside a string or a conditional branch that never runs) costs a refused install, not a silent miss — the safer direction, since the installer cannot assume it may rewrite or replace the project's own hook body to interpose safely.

Resolution: refuse rather than append — print the conflicting file and the line to interpose manually to stderr, exit 1. Consistent with `wire-lefthook.sh`'s existing exit-1-when-unsafe precedent; both `scripts/install/run.sh` and the `SessionStart` sentinel replay call `wire-direct.sh` unguarded under `set -euo pipefail`, so the refusal aborts the caller instead of leaving a half-wired repo. Considered and rejected: silently interposing the gitlore line before the detected `exec` — the inserted line would itself need to avoid `exec` (or it would swallow the *original* hook's tail instead), which means rewriting the existing hook body's control flow rather than just appending, a rewrite too surprising to do unprompted.
