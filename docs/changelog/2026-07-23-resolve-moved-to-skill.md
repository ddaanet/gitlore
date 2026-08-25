# 2026-07-23 — `resolve` moved from `commands/` to `skills/resolve/SKILL.md`, where the design has placed it since 2026-05-26

The design text has called it a self-triggering skill (and required "the
SKILL.md must explicitly orient the agent") since it gained its commit-triggered
entry mode; only the file location lagged, and location is what decides
behavior. A command is a deliberate user action; a skill's description is
matched against context, which is the mechanism by which the agent reaches for
resolve *on its own* when a gate emits `gitlore: memory merge prepared` mid-task
— the dominant entry by far — a mechanical, detectable condition, which is the
skill side of the line. The move costs nothing: a skill is still invocable as
`/gitlore:resolve`, so the three standalone entries survive intact —
`resolve.sh`'s health check with its two non-merge repairs (which now fall
through to the tiers rather than `exit 0`), re-entry after a compaction or in a
fresh session where the hook's directive is no longer in any transcript, and a
divergence surfaced by a `git push` the user ran in their own terminal, where
the directive never reached an agent at all. The description was rewritten to
carry the literal stderr marker plus those user-facing entries, since a skill is
selected on its description alone. `plugin_distribution.bats` gains a regression
asserting the skill exists, that no `commands/resolve.md` shadows it (same name
in both namespaces collides — the same trap the flat-commands test already
guards), that the frontmatter declares `name:` (CC does not fall back to the
filename), and that the marker string is present; verified red against the old
layout.
