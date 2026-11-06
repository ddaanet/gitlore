# Installation and launch mechanism

The literal setup detail `design.md`'s Architecture points at — the install
command's own steps and per-hook-manager wiring syntax — followed by the
decisions that argue for that shape (D25, D45). Motivation stays in `design.md`;
this file is what you need while installing or debugging an install, or while
proposing a change to how any of it is wired. The memory remote the install
creates is in [memory-remote.md](memory-remote.md). The launcher shim and its
two placements are in [memory-redirect.md](memory-redirect.md); the hook wrapper
files are in [hook-wrappers.md](hook-wrappers.md), and what every `SessionStart`
does is in [session.md](session.md).

- **D25** — direct wiring refuses rather than appends after an existing `exec`
- **D45** — the sentinel replay is an allow-list, never `sh -c` on the tracked
  file

*Rejected:* a strictly non-empty initial commit · a separate
`gitlore.memoryPath` config key · replaying the sentinel as a shell command.

---

## The Install Command

`/gitlore:install` — one-time setup, idempotent.

Precondition: must run from the **main worktree** (repo root). In a linked
worktree the memory submodule is typically unchecked-out, so submodule git ops
would silently escape to the parent repo — staging the parent's HEAD as the
memory gitlink and creating branches in the parent. `run.sh` aborts when the
per-worktree git dir differs from the common git dir. As a second line of
defense, `init-submodule.sh` refuses to stage the gitlink when the memory path
has no `.git` (registered but not checked out).

1. Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; if unset, warn and offer to
   enable it (required for sub-agent-based resolve).
2. Prompt for memory path (default: `memory`). If the path exists with unrelated
   content, refuse and prompt for an alternative.
3. Display install-time disclosure: proposed memory remote name, owner,
   visibility (inherited from parent), and notice that memory may contain
   session context. Await acknowledgement (informational, not a hard gate).
4. Create the memory remote with explicit D8 confirmation — see
   [memory-remote.md](memory-remote.md). `gh repo create` (or
   provider-appropriate method) runs. If the parent has no remote, skip; memory
   stays local-only.
5. `git submodule add <remote-url> <path>` (or a local path if no remote) —
   registers the submodule in `.gitmodules` and initializes the empty working
   tree.
6. Seed memory content inside the submodule worktree:
   - If existing auto-memory exists at `~/.claude/projects/<hash>/memory/` and
     holds anything, copy it in. No dir, an empty one, or a migration stub
     copies nothing, the last because the stub's own text says not to add memory
     where it sits.
   - Then scaffold a `MEMORY.md` index file if the store has none — as owed to a
     migration that carried facts but no index as to a store with nothing to
     migrate. A store with no root index composes nothing, no index check guards
     it, and Claude Code loads no memory from it; the scaffold is never skipped,
     and a migrated index is never written over.
7. `git -C <memory-path> add -A && git -C <memory-path> commit -m "Initial memory"`
   — non-empty initial commit; install is git-atomic.
8. Create the `live` branch at the initial commit and check the worktree out
   detached at it (the branch model — `live` is never checked out as a branch).
9. If a remote was created, `git -C <memory-path> push origin live` so the
    parent's submodule pointer is reachable upstream.
10. Write `gitlore.enabled: true` to `.claude/settings.json`; a
    `gitlore.precommitCommand` left by an earlier install is deleted.
11. Emit the memory redirect launcher — `.gitlore/bin/claude` plus the `.envrc`
    `PATH_add` line, both staged for commit — then activate it: `direnv allow`
    when direnv is available (non-fatal; a read-only direnv dir is not a
    blocker), otherwise `global-shim.sh`. Does **not** write
    `autoMemoryDirectory` to any settings file; the launcher injects it at
    launch (D10).
12. Write `gitlore.hooksDir` (abs path to plugin hooks) to local git config.
13. Run hook-manager detection script → apply idempotent wiring, write sentinel
    file.
14. Leave tracked changes staged for the user to commit.
15. When step 6 migrated real facts — announced as
    `gitlore: migrated auto-memory from <src> into <path>`, which a store that
    only scaffolds does not print — the command holds the migrated store against
    the `memory-writing` skill and applies what it finds (D48). Those edits are
    memory content, so they stay uncommitted and reach the user through FR11
    when memory is next committed.

Idempotency rules for re-runs: existing submodule → verify and skip creation;
existing settings keys → overwrite only if value differs; migration → detect
prior migration (by presence of migrated files or a done-marker) and skip;
existing hook-manager wiring with our marker → skip; existing remote → skip
creation. A partial install (user aborted mid-flow) is recovered by re-running.

## Hook Manager Support

**Sentinel file:** `.claude/gitlore-hook-setup` — tracked. Contains the hook
setup command or keyword (`lefthook install`, `npx husky`,
`overcommit --install`, `direct`, or `manual`). `SessionStart` replays it to
re-wire hook-manager integration on a clone or a new machine — by matching the
line against that closed list, never by handing it to a shell (D45).

The detection script outputs structured results. Each hook manager has an
idempotent wiring step (uses marker comment `# gitlore: managed` to detect and
skip duplicates) and a sentinel command stored in `.claude/gitlore-hook-setup`
and replayed by SessionStart on clone or plugin reinstall.

**Detection precedence** (first match wins; multiple detections produce a
warning listing all found managers):

1. `.lefthook.yml` or `lefthook.yml` → Lefthook
2. `.husky/` directory → Husky (v7+)
3. `.overcommit.yml` or `.git/hooks/overcommit-hook` → Overcommit
4. Otherwise → None (direct)

The `direct` case is the default whenever no recognized manager is present —
whether the repo has a hand-rolled `.git/hooks/pre-push` (the direct installer
appends, coexisting) or no hooks at all. The shared `.git/hooks` dir exists in
every git repo, so direct wiring always works, and defaulting bare repos to it
makes the double-commit guarantee (FR8) active out of the box rather than
waiting on a manual copy-paste step. `manual` is **not auto-detected**: it stays
a valid sentinel a user can set by hand, and is emitted for the ambiguous
multi-manager case.

**Wiring** covers `pre-push` only: a memory commit is the agent's own act, so a
parent commit has no gitlore hook (D58). Every manager reaches the wrapper
through `$(git rev-parse --git-common-dir)/gitlore-pre-push` rather than a
literal path (D11), so what differs per manager is only how that command is
spelled and whether a shell expands it. The `gitlore-pre-commit` file in the
common dir is an exit-0 stub, because tracked hook-manager configs written by an
earlier install still name it and are a published boundary the installer does
not rewrite; the direct wiring is not, and removes the `pre-commit` shim it once
wrote, or strips the appended gitlore block from a hand-rolled one, leaving any
other `pre-commit` hook byte-for-byte alone.

*Lefthook* (`lefthook install`) — a `gitlore` command under `pre-push` in
`lefthook.yml`, `run: '$(git rev-parse --git-common-dir)/gitlore-pre-push'`.
Lefthook runs `run` through a shell, so the substitution expands at hook time.

*Husky* (`npx husky`) — a guarded
`exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"` appended to
`.husky/pre-push`, created if missing. Husky runs the script via `sh`, so the
substitution expands.

*Overcommit* (`overcommit --install`) — a custom `gitlore` hook under `PrePush`
in `.overcommit.yml`. Overcommit's `command:` is an array exec'd
**directly, with no shell**, so the wrapper has to be reached through an
explicit one:

```yaml
command: ['sh','-c','exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"','gitlore']
```

The trailing `'gitlore'` sets `$0`, and overcommit appends the applicable files
as `$@`.

*None, i.e. direct* (sentinel `direct`, a keyword SessionStart interprets rather
than runs) — a shell stub at `git rev-parse --git-path hooks/pre-push` that
execs the wrapper. The hooks path is resolved with `--git-path`, not a literal
`.git/hooks/…`, so the `[ -f ]` test and the `cat >` survive a sentinel replay
in a linked worktree.

*Multiple managers, or a hand-set sentinel* (`manual`, also a keyword) — print a
copy-paste snippet and modify nothing. Reached only when detection is ambiguous
or a user sets the sentinel themselves.

**Sentinel handling in SessionStart:**

- `direct` → re-run the direct-wiring installer.
- `manual` → emit `systemWarning` reminding the user to verify wiring.
- `lefthook install`, `npx husky`, `overcommit --install` → run that literal
  command in the repo root.
- Any other value → run nothing; report on `systemMessage` that the sentinel
  names a command gitlore does not replay, and that the user should run it
  themselves or set the sentinel to `manual` (D45).

Idempotency: every wiring modification uses a detection marker
(`# gitlore: managed` or the format-appropriate equivalent). Re-applying is a
no-op.

## Decisions — D25, D45

Why the wiring above has this shape: why direct wiring refuses rather than
appends after an existing `exec`, and why the sentinel replay is an allow-list.

**D25 — Direct wiring refuses rather than appends after an existing `exec`**

`wire-direct.sh` appends its managed block to an existing `.git/hooks/<hook>`
file. `exec` replaces the process, so a pre-existing hook body that already ends
in `exec …` (e.g. `exec just precommit`) makes the appended gitlore block
unreachable dead code — the commit/push succeeds, the project's own gate runs,
and gitlore's sync silently never fires. No warning at install time or commit
time.

Detection is a heuristic, not a shell parse: any non-comment line whose first
token is `exec`. A false positive (an `exec` inside a string or a conditional
branch that never runs) costs a refused install, not a silent miss — the safer
direction, since the installer cannot assume it may rewrite or replace the
project's own hook body to interpose safely.

Resolution: refuse rather than append — print the conflicting file and the line
to interpose manually to stderr, exit 1. Consistent with `wire-lefthook.sh`'s
existing exit-1-when-unsafe precedent; both `scripts/install/run.sh` and the
`SessionStart` sentinel replay call `wire-direct.sh` unguarded under
`set -euo pipefail`, so the refusal aborts the caller instead of leaving a
half-wired repo. Considered and rejected: silently interposing the gitlore line
before the detected `exec` — the inserted line would itself need to avoid `exec`
(or it would swallow the *original* hook's tail instead), which means rewriting
the existing hook body's control flow rather than just appending, a rewrite too
surprising to do unprompted.

**D45 — The sentinel replay is an allow-list, never `sh -c` on the file**

The sentinel is tracked, so it arrives with every clone. Replaying it with
`sh -c "$line"` made the first `SessionStart` in a freshly cloned repo execute
whatever line the clone brought in, gated only by `gitlore.enabled` in the
equally tracked `.claude/settings.json` — an arbitrary-code path that a
contributor, a compromised upstream, or a careless hand edit could reach, and
that ran before the user had read anything. The three manager commands the wire
scripts write are the only lines gitlore ever needs to run, so the replay
matches against exactly those literals; anything else runs nothing and is
reported on `systemMessage` with the way forward. The cost is that a new manager
needs a wire script and an arm here rather than a hand-typed sentinel line,
which is the right cost: a command gitlore runs on a stranger's clone should be
one gitlore shipped.

## Rejected alternatives

**Replaying the sentinel as a shell command.** The `*) sh -c "$cmd"` arm was the
original design, so a user could wire an unsupported manager by writing its
install command into the sentinel by hand. That flexibility is what made the
file an execution vector; `manual` plus a copy-paste snippet covers the same
need without gitlore running the line.

**A strictly non-empty initial commit at install.** Install passes
`--allow-empty` as a safety net: the commit normally carries migrated
auto-memory or a `MEMORY.md` scaffold, but a prior failed install can leave the
migration source a stub, and a hard failure there helps nobody.

**A separate `gitlore.memoryPath` config key.** `.gitmodules` plus the fixed
submodule name `gitlore-memory` is already canonical; a second source is a
divergence risk.
