## Current task

Preflight passed on the current tree — 530/0, clean, submodules clean, docs
audited — so the next action is the release itself. `release` now depends on
the consumer-defined `prerelease` gate (vendored plugin-dev v0.4.0), which
means a plain `just release` will run the evals for the first time.

## Open decisions

- **Bump size.** The scope since `v0.3.0` is two complete design decisions —
  D17 tiered memory and D18 active recall — plus the settled index-authority
  model, which argues for `minor` (0.4.0) over the recipe's default `patch`.
- **What a `pass^5` failure on that first real eval run means.** The three
  scenarios (`03-add-tier`, `04-tier-write`, `05-recall`) have only ever run
  at `EVAL_K=1`, so their reliability at the real bar is unmeasured — a
  failure could indict the scenarios or the code, and the answer changes
  whether the release waits.
