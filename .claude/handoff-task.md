## Current task

Explain why a tier pointer line disappears from the composed root index, and
hold the 0.4.2 tag until it is explained. Two sightings of one symptom:

Live — during three surgical `Edit` calls that only rewrote index hooks,
`ddaanet/feedback_dogfood_early.md`'s bullet vanished from both the root index
and the carrier (root 97→96, carrier 78→77), file on disk untouched. Repaired
and verified (97 / 78 / identical path sets / 0 dangling).

In the suite — `just precommit` is RED: `tests/resolve_compose.bats` test 1
fails at line 73 in the full `bats $(UNIT_TESTS)` run, asserting the merged root
index still holds `- [T](ddaanet/x.md) — org`. Same shape: a tier line dropped
from a composed root index. It passes run alone, and paired with
`index_compose.bats`, `resolve.bats` or `tier_divergence.bats` — so start by
bisecting which of the ~495-case run leaks into it. `make test` runs every unit
suite in one `bats` process, so a shared gitdir, a stray
`refs/gitlore/compose-base`, or an exported `GITLORE_*` are all candidates.

The mechanism to reason from is the three presence flags, not prose about which
side wins: a path at base survives only if both sides keep it, so `b=1, o=1,
t=0` — present at base, present in root, missing from the carrier — deletes the
line from **root** as well. So the question is why the carrier lacked a line the
base still had; upstream retraction is ruled out. Full evidence in
`project_gitlore_global_memory.md`.

The sibling-repo tier migration is the thread waiting behind this one:
`/gitlore:add-tier` per repo (it mounts, activates, recomposes and triages in
one turn), then promote portable facts into `ddaanet/`, `handoff` and `micro`
first for distinct yield.

## Open decisions

- Whether the red test and the live drop are one bug or two. If the suite
  failure turns out to be test-isolation leakage only, the live drop is still
  unexplained and still blocks the tag — decide that explicitly rather than
  letting a green suite close the question.
- `micro` and `general` point their memory submodule at a local
  `./.git/gitlore-placeholder` instead of a GitHub remote. Each one's migration
  session has to settle a real remote before its tier can push — decide whether
  that is worth doing inline or whether they drop to the end of the order.
