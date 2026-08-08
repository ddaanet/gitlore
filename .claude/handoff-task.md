## Current task

No thread is mid-flight. Active recall is `skills/recall/SKILL.md` and nothing
else — decide from the in-context index with no tool calls, at most five
entries, one batch Read. The request file, the `PostToolBatch` hook, the
resolver library and the content-addressed ledger are gone, and `recall-reset.sh`
is reduced to `nudge-reset.sh`. D18 was rewritten around the two measured limits
that sank hook-side injection: `additionalContext` spills past ~2KB into a
pointer file, and injected bytes never satisfy `Read`-before-`Edit`.

The eval was rebuilt on the same seam, because removing the request file removed
the only proof the mechanism had run. Its trigger now reaches the agent solely
as the output of a probe it executes, and the assertion checks that both the
`Skill` call and the body's `Read` follow that call.

## Open decisions

- Whether `CLAUDE.md`'s Recall section keeps prescribing self-recall at two
  checkpoints. Spontaneous invocation is expected to be nil and recall is
  intended as user-triggered; what settles it is dogfooding logs, not argument.
- Whether the skill `description:` keeps advertising an agent-side trigger for
  the same reason. Its conversational wording is what the eval proved fires,
  so the two halves of the description are not equally load-bearing.
- Whether obliging the checkpoint deserves a `Stop` hook. Raised, not designed:
  nothing in the current design detects a skipped recall, and D18 states that
  on non-compliance nothing arrives and nothing reports it.
- What to do with the 14 memory files that still name my human partner directly
  against the shared-tier rule. Most are attributed quotes, where rewriting
  changes how the evidence reads.