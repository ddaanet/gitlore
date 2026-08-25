# 2026-07-31 — A mid-session plugin upgrade is reported, not repaired (D21)

A session whose plugin was upgraded under it keeps running the old version, and
nothing said so. The symptom that surfaced it was a `handoff-checkpoint`
diagnosis blaming an unset `gitlore.hooksDir` when the key was set and pointing
into a version-pinned cache directory the session had frozen at start; two full
cycles of `/plugin`, `/reload-plugins` and hand-rewritten git config went by
before the cause was named.

A probe settled what a live session can and cannot do. Two `-p` runs of a
throwaway `--plugin-dir` plugin whose `SessionStart` hook logged its root, the
payload's `source` and the session id, with `hooks.json` rewritten between them
to name a different script: the resumed run fired `SessionStart` with
`source=resume`, ran the **new** script, and kept the session id. Hook event
registration is per process, not per conversation, and the transcript records no
plugin path or version anywhere — so a resume has nothing stale to restore. Exit
and relaunch with `claude -c` is the whole remedy, and it keeps the
conversation.

That killed both directions that tried to make a live session adopt the upgrade.
A version-less pointer resolved at hook runtime would repoint the git hooks
while CC-side registration, skill bodies and agent definitions stayed behind — a
split-version session, worse than uniform staleness; it also assumed a global
cache pin, where installs are actually pinned per scope and per project.
Wrappers self-healing from `CLAUDE_PLUGIN_ROOT` cannot work at all: that
variable reaches Claude Code hooks only, and a git hook fires from agent Bash.

What remains is to make the failure self-describing. `plugin-upgrade-batch.sh`
compares the frozen root against the install record's entries for this plugin —
user scope plus anything pinned to this project — and speaks once per episode
when the set is non-empty and holds no entry equal to the frozen root, so a repo
deliberately pinned behind the user-scoped version stays silent. The family is
the frozen root's parent directory rather than a `gitlore@ddaanet` literal. The
user-facing line names the remedy, departing from D14's no-instructions style
because only the user can act on it and routing a hot-path notice through the
agent would make it model-dependent; the agent-facing line is mostly the
prohibition, since the observed session had already tried every repair it
forbids.

The cache-prefix guard turned out to be the one that needed a fixture built to
reach it. Its first negative test passed with the guard deleted — the record's
installs sat nowhere near the dev checkout's parent, so the candidate set was
empty for an unrelated reason and the assertion proved nothing. Rewritten so the
record names a sibling of the checkout, which is also the case the guard
genuinely defends: a `--plugin-dir` root's parent is an ordinary source
directory, and a locally-installed plugin recorded under it would otherwise read
as "the version installed here".

`gitlore.hooksDir`'s own stale-cache hint changed with it, from "start Claude
Code in this repo" to `claude -c` — any process start re-pins the five keys, and
the resume is the one that does not throw the conversation away.
