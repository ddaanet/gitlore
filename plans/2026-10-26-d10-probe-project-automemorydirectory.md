# D10 probe — `autoMemoryDirectory` from project settings in CC 2.1.310

D10 rests on Claude Code resolving `autoMemoryDirectory` only from
`policySettings`, `flagSettings` and `userSettings` (read from the resolver in
v2.1.150, observed again for the rejected alternative). This probe re-tests that
premise against CC 2.1.310. It changes nothing in `docs/`; the proposal at the
end is for my human partner to decide.

## Result

CC 2.1.310 honours an **absolute** `autoMemoryDirectory` from both
`.claude/settings.json` and `.claude/settings.local.json`. A **relative** value
is silently discarded. D10's premise, and the rejected alternative's "observed,
not inferred" claim, no longer hold for absolute paths.

| Setting | Value | Memory landed in |
|---|---|---|
| none (control) | — | `~/.claude/projects/<sanitized>/memory/` |
| `--settings` (control) | absolute `<repo>/mem` | `<repo>/mem` |
| `.claude/settings.json` | absolute `<repo>/mem` | `<repo>/mem` |
| `.claude/settings.local.json` | absolute `<repo>/mem` | `<repo>/mem` |
| `.claude/settings.json` | `mem` | default dir, no diagnostic |
| `.claude/settings.json` | `mem`, launched from `<repo>/sub` | default dir of `<repo>` |
| `.claude/settings.json` | `./mem` | default dir, no diagnostic |
| `.claude/settings.json` | absolute path outside the repo | that path |
| `.claude/settings.json` | absolute `<repo>/.git/hooks` | `<repo>/.git/hooks` |

With `--permission-mode default`, the Write into a project-set memory directory
went through with no prompt — inside the repo, outside it, and into `.git/hooks`
— while a control Write outside the repo with no memory setting was refused. The
native memory-write auto-allow therefore follows a project-set path, and CC
applied no containment to it in any case tried. That is not a hole of its own: a
trusted repo's project settings can already register hooks that run arbitrary
commands, and the trust dialog is the boundary for both.

**A setting written during a session does not apply to it.** A `SessionStart`
hook (registered in `.claude/settings.json`) wrote the absolute path into
`.claude/settings.local.json`. That session's system prompt named, and its write
landed in, the default directory; the next launch was redirected. The same held
across two turns of one long-lived process (`--input-format stream-json`, the
path asked in the second turn ~25 s after start), so it is not a race with the
hook. An interactive session (tmux, trust dialog accepted, the hook having
written the file, the path asked ~25 s later) behaved the same: system prompt
and write both in the default directory. The value is fixed at launch.

## Method

One scratch git repo per row under `/tmp/claude/d10probe.*`, the real binary
(`~/.local/bin/claude`, 2.1.310) rather than the gitlore shim, run as
`claude -p --model haiku`. The prompt asked the model to print the auto-memory
directory its system prompt names, then save one fact there with Write and print
the written path. Each row is confirmed twice: the path the system prompt
reported, and the file found on disk afterwards.

## Confounders and limits

- **Trust.** Every run was `-p`, which skips the workspace-trust dialog.
  `~/.claude.json` holds no entry for any scratch directory, so no trust was
  ever recorded: the settings were honoured without one. An interactive launch
  in an untrusted directory was not tested. A gitlore repo is trusted by use, so
  its interactive sessions should match these runs; that too is untested.
- **Permission mode.** My human partner's `defaultMode` is `auto`, which allowed
  every Write, the control included. Only the `--permission-mode default` rows
  carry the auto-allow claim above.
- **Mechanism.** Behavioural only; the resolver in the 2.1.310 binary was not
  read. The `ddaanet/cc-worktree-memory-freeze` memory records the 2.1.219
  bundle reading local and project settings "when trusted", so the behaviour is
  likely older than this probe and deliberate, and D10's 2.1.150 reading may
  have been wrong rather than overtaken.

## What this means for gitlore

The shim is no longer the only per-project mechanism, but project settings are
not a drop-in replacement:

- **Absolute only.** A checked-in `.claude/settings.json` cannot carry a path
  valid on every clone, so the value would live in the untracked, per-checkout
  `.claude/settings.local.json`, written by gitlore (install, and SessionStart
  for a fresh clone or a new worktree).
- **Bootstrap gap (probed).** SessionStart can detect a missing or wrong value
  and write the file, but the session that writes it stays unredirected and
  needs a restart. The shim has no such gap.
- **Containment moves.** CC does none. D68's checks would run where gitlore
  writes the value, not at each launch; a hand-edited `settings.local.json`
  would bypass them, which is no worse than a user's own `--settings`.
- **Worktrees.** Each linked worktree needs its own `settings.local.json` (D11
  anchors wrappers at the common dir; this file is per worktree).
## Proposal

My human partner's criterion: if SessionStart could fix the setting in place, it
would replace the shim; if a restart is needed, the shim keeps the advantage. A
restart is needed, so **keep the shim** and correct the record:

- D10's conclusion stands, re-argued on the bootstrap gap — a launch-time value
  is the only one that redirects the session that sets it — not on CC ignoring
  project tiers.
- The rejected alternative "`autoMemoryDirectory` in `.claude/settings.json` or
  `.claude/settings.local.json`" stays rejected, its reason rewritten: a
  relative value is discarded, so the shared file cannot carry it; the local
  file can, but a value written from SessionStart takes effect only on the next
  launch.
- The redirect node's opening paragraph ("Project settings are *not* honored")
  and the D10 node text follow.
