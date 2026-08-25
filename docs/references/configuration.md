# Configuration

Every file and key gitlore relies on, and what each one is for. `design.md`'s
Architecture states the three-way split; this file is the inventory behind it,
which is what you need while debugging a session that is not healing itself or
a hook that is guarding on the wrong thing.

---

Configuration splits three ways by what has to travel: tracked files travel with
the repo, git-config keys are per-clone and machine-local, and the IPC files are
transient handshakes between the agent and the hooks.

**Tracked — travels with the repo.** `.claude/settings.json` carries
`gitlore.enabled: true` (the activation flag every hook guards on) and
`gitlore.precommitCommand`, the project's own pre-commit check (e.g.
`lefthook run pre-commit`) that the `PostToolUse` nudge watches for.
`.gitlore/bin/claude` is the launcher shim and `.envrc` puts it on `PATH`
(`source_up_if_exists` plus `PATH_add .gitlore/bin`) — see Memory Redirect
Launcher. `.claude/gitlore-hook-setup` is the hook-manager sentinel — the setup
command or keyword (`lefthook install`, `npx husky`, `overcommit --install`,
`direct`, `manual`) that `SessionStart` replays to re-wire hook integration on a
clone or a new machine. Inside the memory submodule, `memory/.gitlore-tiers`
lists the active tiers in precedence order (D30).

**Local git config — never tracked, re-pinned every session.** Five keys point
at the installed plugin, whose cache path changes on every upgrade:
`gitlore.hooksDir` (the hook scripts the wrappers exec), `gitlore.commitCommand`
(`commit-memory.sh`, D16), `gitlore.pushCommand` (`push-memory.sh`, D20),
`gitlore.mergeCommand` (`merge-memory.sh`, D43) and
`gitlore.memoryApprovalClauseFile` (the canonical approval wording, D19). All
five are seeded at install and re-written by every `SessionStart`, which is what
makes them self-healing; each consumer verifies the resolved path before using
it rather than trusting the key (D5).

**IPC files — the agent writes, a hook acts.** `.claude/gitlore-memory-message`
(the approved commit summary), `.claude/gitlore-commit-memory`
(standalone-commit trigger) and `.claude/gitlore-add-tier` (mount intent) all
sit in the parent working tree, gitignored. They live there rather than in a
gitdir because a gitdir write is blocked by the CC sandbox and read as
self-configuration by the auto-mode classifier — the agent can write an ordinary
project file and nothing else. Hook-owned state that the agent must *not* write
goes the other way, into the store's gitdir: the once-per-episode nudge marker
`gitlore-nudged` and the merge-state file.

> **No `autoMemoryDirectory` in project settings.** Claude Code resolves
> `autoMemoryDirectory` only from `policySettings`, `flagSettings` (the
> `--settings` flag), or `userSettings` (`~/.claude/settings.json`) — never from
> project-level `.claude/settings.json` or `.claude/settings.local.json`, which
> it discards for security. The per-project redirect is therefore injected at
> launch by the Memory Redirect Launcher, not written to a settings file. See
> D10.

**Commit message file:** `.claude/gitlore-memory-message`, resolved by
`gitlore_commit_msg_file` from the superproject working tree
(`git -C <memory-path> rev-parse --show-superproject-working-tree`). Claude
writes it once the user has confirmed the commit summary; the commit hook
consumes and deletes it. Its presence is the signal that a memory commit carries
approval (D4).

**Hook wrappers:** `SessionStart` writes `gitlore-pre-commit` and
`gitlore-pre-push` into the repo's **git common dir** on every startup, and each
delegates to the current plugin through `git config gitlore.hooksDir` — so
hook-manager configs name a stable path and plugin updates are transparent.
Resolving through `git rev-parse --git-common-dir` rather than a literal `.git/`
is load-bearing (D11): the common dir is shared across worktrees, so one
emission is reachable and executable from every worktree — including one where
no Claude session has ever run — where `.git/` is a gitlink *file*. Every
producer and every consumer resolves it that way; none hardcode it.

`autoMemoryDirectory` is deliberately absent from this inventory: Claude Code
resolves it only from `policySettings`, `flagSettings` (the `--settings` flag)
or `userSettings`, never from a project tier, which it discards for security.
The per-project redirect is therefore injected at launch by the launcher shim,
not written to a settings file — see D10 in
[memory-redirect.md](memory-redirect.md).
