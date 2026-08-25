# 2026-07-24 — `/gitlore:add-tier` activates as it mounts — dropping the "list it yourself" step, on review that its rationale didn't cover this case

The manifest's "never auto-populate" rule (2026-07-18) was written against
`SessionStart`'s *passive* discovery-by-enclosure, where presence must never
imply activation because a stray submodule could exist for unrelated reasons.
`add-tier.sh` isn't passive — it only runs because the agent's intent file named
*this exact tier* — so that rationale doesn't transfer, and the "half-formed
tier" gap it was guarding (module exists before it self-describes) is invisible
to anything outside the script regardless of who writes the manifest line, since
both modes already converge before either touches it. What's left after removing
that justification is only *precedence* (where a new tier ranks), which doesn't
need withholding activation either — `add-tier.sh` now appends at the bottom
(lowest precedence, the least surprising default) as its own final step, and a
later manual edit to `memory/.gitlore-tiers` still reorders exactly as before.
Because that write happens inside a hook rather than a CC tool call,
`index-compose.sh`'s `.tool_calls[]`-based trigger can't see it; the
recompose-and-report logic was pulled out into a shared
`gitlore_compose_and_report` (`scripts/lib/index-compose.sh`), called by
`index-compose.sh` from a detected touch and by `add-tier-batch.sh` directly
after a successful mount, folding activation, recompose, and the post-mount
triage nudge into one hook response. The dogfooded gap this closes: a mount
always immediately activated in practice (`ddaanet`, `onekeys`) — the "mount
without activating" state the two-step design preserved was never exercised. 43
cases across `tests/add_tier.bats` and `tests/cc_hook_add_tier.bats`, including
a new case pinning the bottom-of-list default when a tier is already active.
