Landed the compose resurrection-bug fix (root/carrier merge drops a carrier
line once root has an established block for that tier) as commit 420d9dc,
with tests, the plan brief, and a memory catch-up. The narrower residual gap
described in docs/plans/brief-compose-full-tier-clear-gap.md — clearing every
root-authored line for an active tier in one edit doesn't propagate — is
still open, not started.

## Open decisions

- How (or whether) to close the full-tier-clear gap: accept and document as
  is; add a persisted last-synced marker per tier; detect the touch via the
  actual tool-call diff instead of post-hoc file comparison; or require a
  full-tier clear to go through an explicit deactivate/remount action instead
  of hand-editing every root line out.
