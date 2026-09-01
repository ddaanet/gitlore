# 2026-09-01 — A local `live` stranded behind HEAD is advanced, not reported

`/gitlore:push` in a repo running 0.5.0 failed on a `ddaanet` tier that was
36 commits behind its remote and had nothing to publish:

```text
Already up to date.
gitlore: could not prepare the memory merge against 'origin/live'. Inspect the memory worktree at memory/ddaanet.
```

That push-side misclassification is already fixed — a refusal is classified by
ancestry, a behind store is taken rather than merged, and a failed preparation
restores the HEAD it moved. What the incident added is the state the old
preparation left behind and the blind spot that made it permanent: the
diagnosis had checked HEAD out at `origin/live` and never moved `live`, the
ref a push sends. `gitlore_merge_one_store` classifies a store by ancestry
against `origin/live` **read from HEAD alone**, so the remote was now
contained in HEAD and every subsequent `/gitlore:merge` — the remedy the
failure text names — answered `already holds everything its remote does` and
returned 0, while the next push was refused identically. Recovery took three
hand-run git commands.

`live` strictly behind a HEAD that contains it can only mean `live` failed to
keep up: a store rests detached *at* `live`, every commit in HEAD arrived
through a gate, and no path produces a HEAD deliberately ahead. So it is
advanced with the same local, ff-checked `push .` the fast-forward arm already
performs as a side effect, and the store that was repaired is named. Nothing
reaches a remote.

Both halves of the publish do it, ahead of the report each would otherwise
make. A take repairs before printing `already holds everything its remote
does`, so a store about to fail on its refs is never first told it is
finished. The push preflight repairs before `gitlore_check_head_live_agree`
runs, replacing a message whose whole content was one git command the user
would then paste back — a round-trip with nothing in it to decide. The
preflight's other directions are unchanged, and the check stays report-only:
a `live` *ahead* of HEAD keeps its "put HEAD back" remedy, since that is D43's
pin or a publication awaiting its push.

The repair itself reports and moves nothing when HEAD and `live` have each
moved, since which was intended is not recoverable from the refs. The take
kept its own wording for that rather than reaching for
`gitlore_check_head_live_agree`'s, which ends in "so nothing was published" —
a claim about a publish a take never attempts.

The local-advance sites — the tier and memory `live` sync, and the resolve
continuation's `check_store_gates` — are unchanged. Each already runs
`push . HEAD:live` unconditionally as its first act, which is the repair, and
reaches the drift check only when that push was refused. There, `live` behind
HEAD means the ref moved under the push rather than lagging it, so the check
keeps the arm that says so.

Cases in `tests/merge_memory.bats` and `tests/push_behind_vs_diverged.bats`,
each watched red first: the field state on the root store and on a tier, the
divergence that must not be repaired, and the push that now publishes the
commit its gitlink records instead of reporting drift. The existing "already
holds everything" test passed throughout because its fixture has HEAD ==
`live`, which is why the blind spot survived the suite.
