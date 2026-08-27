## Brief: `commit-memory.sh` has no companion skill

2026-08-15

### Decisions

- Every other standalone memory-administration entry point has a companion
  skill under `skills/`: `push-memory.sh` → `push`, `resolve.sh` → `resolve`,
  `merge-memory.sh` → `merge`. `commit-memory.sh` has none, despite its own
  header calling it a "Standalone blessed entry point (D16): commit the
  memory submodule and advance local `live` without a parent commit."
- Recommendation (not yet reviewed by anyone with gitlore context — just a
  finding from a downstream session): add a `commit` skill that owns writing
  the approved summary to `.claude/gitlore-memory-message` in the required
  format, invoking `commit-memory.sh`, and reporting the outcome — the same
  shape `skills/push/SKILL.md` already uses for `pushCommand`.

### Constraints

- `git config gitlore.commitCommand` resolves to
  `scripts/commit-memory.sh`, parallel to `gitlore.pushCommand` /
  `gitlore.resolveCommand` / `gitlore.mergeCommand`. A new skill should read
  the command the same way `push`'s skill body does:
  `bash "$(git config gitlore.pushCommand)"`.
- The FR11 approval-summary format is already fixed elsewhere (the
  `PreToolUse` hook that denies a plain `git commit` on dirty memory states
  it): subject line, blank line, one paragraph per changed memory file, each
  opening with a bold prefix — New / Update / Augment / Reduce / Remove —
  naming `<tier>/<slug>`. A `commit` skill needs to reproduce or reference
  that same template so a caller isn't reconstructing it from the denial
  message each time.
- `commit-memory.sh`'s header describes it as "Arg-driven, git-commit-style"
  — its actual CLI (flags, message input) wasn't read past the header in the
  downstream session; check it before drafting the skill body.

### Rejected approach

- Discovering and invoking `commit-memory.sh` ad hoc via
  `git config gitlore.commitCommand` from a consuming repo. It works
  mechanically, but every other command has a skill that guides correct
  usage (format, reporting), and this one doesn't — the gap is what this
  brief is about, not a fix landed in place.

### Additional context

Surfaced in a `claude-plugin-dev` session while resolving a diverged
`ddaanet` tier merge and publishing memory via `/gitlore:push`. Partway
through, a fast-forward pulled in a new fact
(`ddaanet/gitlore-memory-administration-no-parent-commit.md`, written by a
concurrent session) recording that administering memory alone — a merge, a
trim, a curation pass, with no accompanying parent-repo content — needs no
parent-repo commit; writing the approved summary is enough on its own. That
fact was itself prompted by the same mistake this brief's author had just
made: manufacturing an unrelated parent "chore" commit purely to unblock a
"memory is dirty and has no approved commit summary" gate, when writing the
summary and calling `commit-memory.sh` directly would have sufficed.

Both sessions independently reached for `commit-memory.sh` by grepping git
config rather than through a guided skill — the recurrence across two
unrelated sessions on the same day is the signal that this is a structural
gap, not a one-off. A `commit` skill would give this recovery path (memory
needs committing, no parent-repo change accompanies it) the same discoverable,
guided shape `/gitlore:push` and `/gitlore:resolve` already give their own
paths.


### Assessment (gitlore, 2026-08-27) — recommendation not adopted

The finding is real: `commit-memory.sh` is the only standalone entry point with
no companion skill, and two sessions reached it by grepping `git config`. The
recommended fix contradicts a decision this repo took deliberately, so it is
not implemented pending my human partner's call.

`docs/references/commit-gate.md` states the scoping: the standalone commit is
the `handoff` plugin's path, not the general one (D16), and the trigger is *kept
out* of the general agent-facing instructions — the SessionStart orientation,
the nudge and the gate's block message all describe only the message-file plus
parent-commit path — "so an agent not running the handoff skill is never taught
it can force a standalone memory commit." A skill's `description` is injected
into every session, so shipping `/gitlore:commit` teaches exactly that, to every
agent, in every repo that mounts gitlore.

The brief's proposed body would also not work as written. The agent cannot run
this path itself: `commit-gate.md` records that the standalone commit goes
through an intent file plus a `PostToolBatch` hook precisely because it
sidesteps the command sandbox and the auto-mode classifier, "neither of which
lets the agent do this work itself".
`bash "$(git config gitlore.commitCommand)"` is the shape `push` uses because
publishing an already-approved commit needs no such handling; committing does.

What the recurrence actually costs is already covered by a memory fact —
administering memory alone needs no parent commit: write the approved summary
and stop. The open question is therefore not "skill or no skill" but whether
that path deserves more surface than a memory line: a sentence in the gate's own
block message, which reaches an agent exactly when it is stuck, costs no
per-session context and teaches no force-commit trigger.

Options, for my human partner:

1. Leave it as is — the gap is a discoverability one that memory already closes.
2. Extend the gate's block message with the standalone-administration sentence
   (no new skill, no new always-on context, reaches the agent at the moment of
   the block).
3. Ship the `/gitlore:commit` skill as the brief recommends, and revise D16's
   scoping in `commit-gate.md` accordingly, accepting that every session learns
   the standalone path.
