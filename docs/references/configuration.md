# Configuration

Every file and key gitlore relies on, and what each one is for. `design.md`'s
Architecture states the three-way split; this file is the inventory behind it,
which is what you need while debugging a session that is not healing itself or a
hook that is guarding on the wrong thing.

---

Configuration splits three ways by what has to travel: tracked files travel with
the repo, git-config keys are per-clone and machine-local, and the one IPC file
is a transient handshake between the agent and a hook.

**Tracked — travels with the repo.** `.claude/settings.json` carries
`gitlore.enabled: true`, the activation flag every hook guards on.
`.gitlore/bin/claude` is the launcher shim and `.envrc` puts it on `PATH`
(`source_up_if_exists` plus `PATH_add .gitlore/bin`) — see Memory Redirect
Launcher. `.claude/gitlore-hook-setup` is the hook-manager sentinel — the setup
command or keyword (`lefthook install`, `npx husky`, `overcommit --install`,
`direct`, `manual`) that `SessionStart` replays to re-wire hook integration on a
clone or a new machine. Inside the memory submodule, `memory/.gitlore-tiers`
lists the active tiers in precedence order (D30).

**Local git config — never tracked, re-pinned every session.** One key points at
the installed plugin, whose cache path changes on every upgrade:
`gitlore.hooksDir` (the hook scripts the wrappers exec). It is seeded at install
and re-written by every `SessionStart`, which is what makes it self-healing;
each consumer verifies the resolved path before using it rather than trusting
the key (D5). The three entry points are reached by the plugin `bin/` names
`gitlore-commit`, `gitlore-push` and `gitlore-merge`, which need no key (D70).

**IPC file — the agent writes, a hook acts.** `.claude/gitlore-add-tier` (mount
intent) sits in the parent working tree, gitignored. It lives there rather than
in a gitdir because a gitdir write is blocked by the CC sandbox and read as
self-configuration by the auto-mode classifier — the agent can write an ordinary
project file and nothing else. Hook-owned state that the agent must *not* write
goes the other way, into the store's gitdir: the once-per-session
`gitlore-budget-nudged-<session>` and `gitlore-upgrade-nudged-<session>`
markers, the merge-state file, the index pair's per-batch baselines
`gitlore-index-preimage[-<agent>]` and `gitlore-compose-stamp[-<agent>]` (D31,
suffixed by the agent id inside a subagent), a tier's `gitlore-tier-landing`
record of the commit a tier commit started from (D50), and the relay reports
`gitlore-relay-<session>-<agent>-<epoch>-<pid>-<tag>` — one per report a hook
staged from inside a subagent, built at `<name>.tmp`, removed by the drain that
delivers it to the parent (`relay-drain.sh`, or `SessionStart` folding it into
its own report) or by the seven-day sweep (D51).

> **No `autoMemoryDirectory` in project settings.** Project-level
> `.claude/settings.json` and `.claude/settings.local.json` honor only an
> absolute value, fixed at launch: a relative one is discarded, and one written
> during a session redirects only the next launch. The per-project redirect is
> therefore injected at launch by the Memory Redirect Launcher, not written to a
> settings file. See D10.

**Hook wrappers:** `SessionStart` writes `gitlore-pre-commit` and
`gitlore-pre-push` into the repo's **git common dir** on every startup.
`gitlore-pre-push` delegates to the current plugin through
`git config gitlore.hooksDir` — so hook-manager configs name a stable path and
plugin updates are transparent. `gitlore-pre-commit` is an exit-0 stub, kept for
tracked hook-manager configs that still name it (D58). Resolving through
`git rev-parse --git-common-dir` rather than a literal `.git/` is load-bearing
(D11): the common dir is shared across worktrees, so one emission is reachable
and executable from every worktree — including one where no Claude session has
ever run — where `.git/` is a gitlink *file*. Every producer and every consumer
resolves it that way; none hardcode it.

`autoMemoryDirectory` is deliberately absent from this inventory: a project tier
honors only an absolute value, fixed at launch, so a value written from
`SessionStart` would not redirect the session that wrote it. The per-project
redirect is therefore injected at launch by the launcher shim, not written to a
settings file — see D10 in
[memory-redirect.md](memory-redirect.md).
