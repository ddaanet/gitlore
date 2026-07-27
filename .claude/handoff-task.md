## Current task

Two threads. The **open-decisions walk** through the handoff list, in
presentation order: the compose-base thread closed (`refs/gitlore/compose-base`
is an audit chain now), and the remaining two are analysed and waiting on a
call from David — both are below with the evidence they turn on. The **memory
proof pass**, items 9-16 — eight local memory files judged in presentation
order on whether each fact still earns its place or is already owned by
`docs/design.md`/`CLAUDE.md`, then a cross-cutting sweep — is not started.

## Open decisions

- `scripts/check-version.sh`: delete, or keep and repair. The hole it guards is
  real and is the one gap between the two ends that were thought to close it:
  `plugin-dev/release.just` bumps the marketplace **after** `git push`,
  `git push origin $tag` and `gh release create`, so any failure from
  `gh release create` onward leaves the plugin tagged and pushed with
  `marketplace.json` stale. Nothing else covers that window — the recipe's
  pre-flight compares `plugin.json` against the latest tag only, and
  `version-guard.sh` fires on `PreToolUse(Write|Edit)` against `plugin.json`
  only, not `marketplace.json`, not a human editor, not a half-finished
  release. But it is mis-wired three ways: it hardcodes `../claude-plugins`
  while the recipe uses `$MARKETPLACE_DIR` (a mismatch makes it `exit 0` with
  "skip", a guard reporting success when it never ran), it hardcodes
  `select(.name=="gitlore")` where the recipe reads `.name` from the manifest,
  and its header still says `make check-version`. Recommendation: keep, fix all
  three, and move it into `plugin-dev/` beside the recipe whose window it
  guards — the `git subtree push` to `claude-plugin-dev` stays David's.

- `tests/evals/lib/judge.sh`: whether the three-state exit lands before any
  hardening of the verdict parse. `case "$first_word" in pass) exit 0 ;; *)
  exit 1` collapses three states — the judge said *fail*; the judge answered
  unparseably (`Pass.` survives `tr` but `awk '{print $1}'` yields `pass.`, no
  match); and `claude --print` never ran, with `2>/dev/null` discarding the
  reason. Both call sites (`asserts/memory-commit.sh:59`,
  `asserts/tier-write.sh:145`) turn any non-zero into
  `fail "commit message failed judge rubric"`, so an unavailable judge is
  reported as a rubric regression. Hardening the parse first strictly worsens
  reporting: it raises the unparseable rate while each new instance still
  arrives disguised as a rubric failure. Proposed: 0 pass / 1 fail / 2
  invalid-or-unavailable, drop the `2>/dev/null`, surface the captured stderr
  on the exit-2 path, call sites branch on 2 to an eval *error*. No mention in
  `docs/design.md` either way.

- The vanished pointer stays undiagnosed, and the audit chain does not close
  it. The chain records from this point forward; the pass that dropped that
  line left nothing behind. It also never leaves the machine —
  `refs/gitlore/compose-base` is outside `refs/heads`, so nothing pushes it and
  a fresh clone starts blank.
