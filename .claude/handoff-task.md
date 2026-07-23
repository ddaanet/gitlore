## Current task

The branch is heading for a release. The nine findings from the review of the
unpushed shell changes are all fixed, each with a bats test verified red against
the old code, and `just precommit` is green (540 tests, shellcheck clean on 117
files). What remains is the release itself, whose open questions are below.

## Open decisions

- **Bump size.** Scope since `v0.3.0` is two complete design decisions — D17
  tiered memory and D18 active recall — plus the settled index-authority model,
  which argues for `minor` (0.4.0) over the release recipe's default `patch`.
- **What a `pass^5` failure on the first real eval run means.** `just release`
  depends on the consumer-defined `prerelease` gate (vendored plugin-dev
  v0.4.0), so it runs the evals for the first time. Scenarios `03-add-tier`,
  `04-tier-write` and `05-recall` have only ever run at `EVAL_K=1`, so a failure
  could indict the scenarios or the code — and the answer decides whether the
  release waits.
- **322 unticked checkboxes across nine `docs/plans/*.md`** — reconcile them or
  accept them as historical artifacts. Preflight reports them as pending work on
  every run.
- **`/gitlore:resolve` is undocumented in the README**, which covers only
  `/gitlore:install` and `/gitlore:add-tier`. Document it before the release, or
  ship it undocumented.
