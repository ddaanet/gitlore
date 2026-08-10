## Current task

Release preparation for the plugin. `ddaa:preflight` was interrupted after its git-state step, so its quality checks, documentation audit and scope assessment have not run. Its clean-tree verdict on the memory submodule is settled — that carve-out is now a shared-tier fact, and the gate should be re-entered from step 3.

## Open decisions

- Whether `CLAUDE.md`'s Recall section keeps prescribing self-recall at two checkpoints. Spontaneous invocation is expected to be nil and recall is intended as user-triggered; what settles it is dogfooding logs, not argument.
- Whether the skill `description:` keeps advertising an agent-side trigger, for the same reason. Its conversational wording is what the eval proved fires, so the two halves of the description are not equally load-bearing.
- Whether obliging the recall checkpoint deserves a `Stop` hook. Nothing detects a skipped recall, and on non-compliance nothing arrives and nothing reports it.