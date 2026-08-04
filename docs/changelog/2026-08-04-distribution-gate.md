# 2026-08-04 — The shipped surface got its own gate, so a skills-only edit stops reporting cached

`precommit_inputs` leaves `agents`, `commands` and `skills` out on purpose: the
full bats suite takes 7m30s on this box, and an edit to a skill's prose must
not pay it. But `prerelease` is `precommit`, so nothing on the release path
re-read the three directories the plugin actually distributes. A change
confined to them moved no hash, the gate printed `precommit: cached`, and every
assertion on the edited file went unrun — on the commit that made the change
and on the release that shipped it.

The justfile documented the exclusion as a trade whose cover was `just evals`,
whose input set does include the three. That cover does not exist in practice:
evals drives the real CLI, costs time and money, and is deliberately not a
release dependency.

The hole was latent rather than live. Both commits since v0.4.4 that touched
those directories also touched `scripts/` and `tests/`, which are declared, so
the hash moved and the suite ran. Nothing shipped unchecked; the gate was one
distribution-only commit away from letting it.

`check-distribution` now runs `tests/plugin_distribution.bats` behind its own
sentinel, keyed on `distribution_inputs`, and hangs off `precommit` — so off
`prerelease`, and so off `release`. It is a separate recipe because
`check-sentinel` sets `sentinel` and `gate_inputs` for `record-sentinel` to
read back, and two gates sharing one shebang body would have the second clobber
the first's state. Its input set is everything the suite reads, not the
narrower set precommit happens not to cover: that overlap costs a redundant 2s
run when `scripts/` or `hooks/` change, and buys a gate that is a pure function
of its own inputs, immune to how the other set is later drawn.

Widening `precommit_inputs` instead was measured and rejected — 7m30s against
the distribution suite's 2s, paid on every prose edit to a skill body.

Two structural tests moved out of hook suites and into
`tests/plugin_distribution.bats`, which is what made `precommit`'s remaining
suites read outside their own hash: `cc_hook_recall.bats` asserted on
`skills/recall/SKILL.md`, and `cc_hook_add_tier.bats` on
`commands/add-tier.md`. A grep over the whole suite confirms those were the
only two. The add-tier assertion was already covered by the existing
flat-commands test, so it folded in rather than landing twice; that test's
`[ ! -d commands/gitlore ]` tightened to `-e` on the way, since a plain file by
that name is equally not a command.

`tests/justfile_gates.bats` gained cover for the wiring itself. The declared-
inputs-exist check now loops over `distribution_inputs` too, the
discover-by-glob check admits the one deliberately named suite while still
rejecting any other literal, and a new test reads `just --dump --dump-format
json` to assert both edges — `precommit` depends on `check-distribution`, and
`prerelease` depends on `precommit`. Dropping either edge would restore the
blind spot without failing anything else. All three were verified red by
breaking them.

The gate's coverage was proven rather than reasoned about: run twice for
`cached`, then one throwaway line appended to a file in `agents/`, `commands/`
and `skills/` in turn, each confirming a real run, each reverted to an empty
diff.
