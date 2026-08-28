# 2026-08-28 — The authoring skill is invoked at the three moments that act on facts already written (D48)

D47 shipped `memory-writing` and left it to reach the agent the way any skill
does — a description matched against the moment a fact is drafted. That covers
the write. It does not cover the moments where the facts already exist and no
write is in flight, which is where the discipline was actually being applied by
hand, on a reminder: the approval summary at the commit gate, a store just
migrated in by `/gitlore:install`, and the local facts a newly mounted tier's
scope might now cover. Each of those moments already has gitlore text arriving
at the agent, so the trigger is a sentence in text that already fires — no new
hook, and nothing added to always-on context. The `PreToolUse` deny D47
rejected stays rejected; a directive at a moment gitlore already speaks at is
the cheap half of what that hook was for.

At the gate the directive rides the canonical approval clause rather than the
three internal call sites' own framing, so it also reaches the fourth site: the
`handoff` plugin's checkpoint, which discovers the clause through
`gitlore.memoryApprovalClauseFile` and would otherwise commit memory with the
discipline unapplied — exactly the drift D19 exists to prevent. The clause is
now two blocks, review directive then body spec, and the order is load-bearing:
an edit made after the summary describes a commit that no longer matches, and
`gitlore_commit_msg_freshness` would invalidate the approval anyway.

Install's review had nothing to condition on — the first-install migration
copied auto-memory in silently, and only the re-run catch-all announced
anything. `init-submodule.sh` now prints `gitlore: migrated auto-memory from
<src> into <path>` on the branch that copies real facts, and the scaffold
branch stays silent because a store gitlore seeded itself has nothing to hold
against the skill. The review's edits land uncommitted on top of the
installer's `Initial memory` commit and reach the user through FR11 on their
first parent commit.

The mount's trigger went into the post-mount triage nudge as well as the
command body, because the nudge fires on any manifest change — including a hand
edit of `.gitlore-tiers` by an agent that never ran `/gitlore:add-tier`. Both
name the skill rather than restating its tier test. `SKILL.md` gained the
batch order these three moments need: discard and relocate first, then bodies,
then index lines, all before the summary; an index over the loader cap remains
`/gitlore:index-audit`'s decision, not the gate's.

The bats suites hold what they can see — each site naming the skill, the
directive preceding the body spec, the announcement firing on the migrating
branch and not the scaffold one. Whether the agent invokes the skill on being
told to is agent behaviour and belongs to the eval tier.
