# Hook wrappers — decisions D5, D11

The wrapper files `SessionStart` writes into the git common dir: where they live
(D5), why they are anchored at the common dir rather than a literal `.git/` so
that a linked worktree reaches them (D11), and how a wrapper degrades when the
plugin it pins is unset or gone. Read it while debugging a git operation that
fails or skips at a gitlore wrapper, or while changing how a wrapper is written
or wired. What every `SessionStart` does around the emission is in
[session.md](session.md); the install command and the per-manager wiring that
name the wrapper are in [installation.md](installation.md).

- **D5** — wrapper scripts live in the git common dir, untracked
- **D11** — wrapper paths are gitlink-aware, anchored at the git common dir, so
  linked worktrees work

*Rejected:* tracked hook scripts in the repo · a literal `.git/gitlore-<hook>`
wrapper path · a per-worktree wrapper anchor.

---

## Hook Wrappers

`SessionStart` writes two flat files into the repo's **git common dir** on every
startup, resolved via `git rev-parse --git-common-dir`:

- `<common-dir>/gitlore-pre-push`, the wrapper below
- `<common-dir>/gitlore-pre-commit`, an exit-0 stub kept for tracked
  hook-manager configs that still name it (D58)

The common dir is shared across all worktrees (`--git-common-dir` → `.git` in
the main worktree, `<main>/.git` in a linked one), so one emission is reachable
and executable from every worktree — including one where no Claude session has
ever run. Every producer (`emit-wrappers`) and every consumer (the wired stubs
and manager configs) resolves the wrapper through `--git-common-dir`; none
hardcode `.git/`, which is a gitlink *file* in a linked worktree. See D11.

The wrapper delegates to the current plugin via `git config gitlore.hooksDir`
(regular git config, shared across worktrees via the common config). Stable
paths for hook manager configs; plugin updates are transparent. The pin selects
which hook script a wrapper runs; the script itself sources the libraries beside
its own path, so a hook script and its libraries always come from one tree even
when the pin lags. If `gitlore.hooksDir` is unset (a plain `git push` outside
any Claude session before SessionStart has fired), the wrapper exits 0 after
emitting a stderr hint — `"gitlore skipped: hooks not installed"` plus
instructions to install the marketplace, plugin, and start Claude.

```sh
#!/bin/sh
HOOKS_DIR=$(git config gitlore.hooksDir)
if [ -z "$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "$HOOKS_DIR/pre-push" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Relaunch Claude Code in this repo with 'claude -c' to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "$HOOKS_DIR/pre-push" "$@"
```

## Decisions — D5, D11

Why the wrappers live where they do and how they are anchored.

**D5 — Wrapper scripts in the git common dir, not tracked**

Tracking hook scripts in the repo would cause commit churn on every plugin
update and couple the repo's history to the plugin's versioning. Storing flat
wrappers in the git common dir (`<common-dir>/gitlore-pre-push`, resolved via
`git rev-parse --git-common-dir`) keeps them untracked and local. `SessionStart`
regenerates them on every startup, so they always reflect the current plugin
version. The common dir (rather than a literal `.git/`) is what makes the
wrappers reachable from linked worktrees, where `.git` is a gitlink file — see
Hook wrappers above and **D11**.

Wrappers exec the real hook scripts via `$(git config gitlore.hooksDir)/<hook>`.
The wrapper degrades to a clean skip (exit 0 + stderr hint) in **two** cases,
not one:

1. **`gitlore.hooksDir` unset** — a plain `git commit` outside any Claude
   session before SessionStart has fired. Hint: install the marketplace, plugin,
   and start Claude.
2. **`gitlore.hooksDir` set but `$HOOKS_DIR/<hook>` does not exist** — the
   version-pinned config points at a plugin-cache dir that was GC'd after a
   plugin upgrade, in the window before the next SessionStart re-pins it.
   Without this guard the wrapper `exec`s a missing path and the commit/push
   **hard-fails** with `exec: …: not found`. Hint: relaunch with `claude -c`.

Both keep git operations unblocked rather than breaking a commit on a
transient/stale-config condition.

**The refresh is `claude -c`, not a cold session.** Any process start re-pins
the key — `SessionStart` fires on a resume as it does on a startup, with
`source=resume` (D21, [plugin-upgrade-notice.md](plugin-upgrade-notice.md)) — so
a resume closes the staleness window while keeping the conversation that hit it.
A cold session closes the same window and throws the context away. This is the
same remedy the upgrade notice names, for the same reason: what went stale was
frozen at process start, and only a new process re-reads it.

**D11 — Gitlink-aware wrapper paths (common-dir anchor) for linked-worktree
support**

A literal relative `.git/gitlore-<hook>` in the wrapper writer (`emit-wrappers`)
and in the hook-manager consumers works only where `.git` is a directory — the
main worktree. In a linked worktree `.git` is a gitlink *file*, so the path
fails on both sides: `cat > .git/gitlore-*` aborts SessionStart under `set -e`,
and the shared wired hook (which lives in the common dir and therefore fires in
*every* worktree) `exec`s the literal path and **blocks the git operation**
(`exec: … not found`). Both verified empirically against git 2.47.3.

The wrapper is therefore anchored at
`$(git rev-parse --git-common-dir)/gitlore-<hook>` on both the write and exec
sides, across all managers (direct, husky, lefthook, overcommit, manual). The
common dir is shared, so one emission covers every worktree, including a
session-less linked worktree (plain `git worktree add` + `git commit`).

Considered and rejected: a **per-worktree** anchor via
`git rev-parse --git-path gitlore-<hook>` (which resolves to
`…/worktrees/<name>/gitlore-<hook>`). It reintroduces the commit-blocking gap in
any worktree where no session has run yet, because the shared wired stub would
`exec` a per-worktree wrapper that does not exist. The common-dir anchor has no
such gap. (The wrapper is one shared executable.)

Corollary fix: once the wrapper *fires* in a linked worktree, the git-hook runs
`git -C "$mempath" …` under `set -e`. If the memory submodule worktree was never
created there (session-less worktree), this would abort and block the push for a
*new* reason. `pre-push` therefore guards with an early
`[ -e "$mempath/.git" ] || exit 0` — nothing to sync, never block.

## Rejected alternatives

**Tracked hook scripts in the repo.** Commit churn on every plugin update, and
it couples the repo's history to the plugin's versioning.

**A literal `.git/gitlore-<hook>` wrapper path.** Fails in a linked worktree,
where `.git` is a gitlink file: the write aborts SessionStart and the exec
blocks the git operation. Replaced by the common-dir anchor (D11).

**A per-worktree wrapper anchor** (`--git-path gitlore-<hook>`). Reintroduces
the commit-blocking gap in any worktree where no session has run, because the
shared wired stub would exec a per-worktree wrapper that does not exist. The
common-dir anchor has no such gap (D11).
