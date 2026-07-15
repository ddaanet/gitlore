## Current task

Dogfood the index→frontmatter sync's new `PostToolBatch` path against a real
memory edit — it could not run this session, whose hook registration is frozen
on the old per-call event — then write the D17 reconcile-slice plan.

## Open decisions

- Whether "index one-liner canonical" (D17's premise) survives its authoring
  cost, now that the sync reports what it replaced instead of discarding it
  silently. The doubt rested on the agent authoring a considered `description:`
  only to have the terser index hook overwrite it unannounced; the reporting
  pass removes the silence without touching the direction, so the question is
  now whether the *remaining* cost (two writes per fact) still outweighs the
  retrieval win (always-loaded, 100% vs 75% recall). Settle before reconcile,
  which applies the rule at scale over ~40 stale-index files. Unexplored
  reframing: frontmatter authoritative at authoring, index derived at commit.
- Whether `PreToolBatch` exists and fires for a single tool call. It would pair
  with `PostToolBatch` and retire the "first index edit of the batch stashes,
  later ones must not" rule plus the stash-clearing-on-untouched-batch guard.
  Absent from the hooks reference and unverified; probing it means a temporary
  hook in `settings.local.json`, which the auto-mode classifier blocks as
  self-modification, so it needs explicit user authorization.
- Where the memory-commit magic file lives. Decided in principle: move to
  `.claude/gitlore-memory-message` (the name leaves room for nested repos, e.g.
  `.claude/gitlore-memory-ddaa-message/`), needs a `.gitignore` entry.
  Load-bearing: the gitdir path is unwritable by the agent under auto mode via
  any tool, so the intended one-call handoff cannot execute at all. Open
  sub-question: whether `pre-commit` should print the direction on a plain run,
  so the message can be written in the same turn as the commit.
- Whether a net-new index line propagating is intended D17 behavior or scope
  creep. The slice-1 plan lists net-new-line seeding as out of scope, but an
  absent pre-image entry reads as "changed", so a brand-new index line does
  overwrite an existing `description:`. Only a file with no `description:` line
  at all is genuinely unseeded, since the setter matches `^description:`.
- Whether the incoming `note-for-gitlore.md` request lands: the memory gate
  should tell the agent to present its proposed commit summary as a markdown
  blockquote rather than a code fence, which frames prose as an artifact to copy
  verbatim instead of a draft to edit. A prompt fix in the gate's own text, in
  two places (the probe/gate output and the `pre-commit` block).
