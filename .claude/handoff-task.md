## Current task

Branch `tier-triage-nudge` implements the add-tier post-mount triage-nudge
design (`docs/superpowers/specs/2026-07-24-add-tier-triage-nudge-design.md`):
`add-tier-batch` now runs before `index-compose` in `PostToolBatch` so a
one-turn intent+manifest write mounts and activates a tier together, and a
manifest change nudges the agent to triage local memory against every active
tier's live frontmatter scope (never a fixed dichotomy). All five Components
are built and TDD'd; `just precommit` is green.

## Open decisions

- Whether to dogfood the one-turn flow live before trusting it beyond bats
  coverage — either `just prerelease` (the `03-add-tier` eval scenario
  already prompts a one-turn mount-and-activate, so it now exercises the new
  ordering) or a manual `/gitlore:add-tier` mount in a throwaway repo. Costs
  real API time either way, so it was deferred rather than run.
- Whether to merge `tier-triage-nudge` into `main` now or hold it for review
  first.
