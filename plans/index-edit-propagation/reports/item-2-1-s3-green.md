# Item 2.1 slice 3 — GREEN

## Implementation

`scripts/cc-hooks/index-sync-post.sh` already held the full hook payload in
`$payload` (line 21, unchanged). Added one line reading the agent id from it,
right after the existing `session=…` read:

```sh
agent_id=$(jq -r '.agent_id // empty' <<<"$payload")
```

**No fallback** — `.agent_id // empty` only, per the test review's finding that
a fallback to `agent_type` keys the parent's own batch as a subagent's and is
now pinned by `tests/index_sync.bats:689`. Mirrors `index-sync-pre.sh:40`
exactly (slice 2).

`$agent_id` is passed as the second argument to the file's one resolution of the
pre-image baseline:

```sh
stashfile=$(gitlore_index_preimage_file "$mempath" "$agent_id")   # absolute
```

That is the only site this file resolves the pre-image name. Both `rm -f` sites
— the cmp-equal early exit (`:39` before the edit, unchanged line content) and
the unconditional cleanup near the end (`:146`-ish) — already read `$stashfile`,
the same variable, so keying the resolution keys the removal too without a
second edit. Confirmed no other reference to `gitlore_index_preimage_file` or to
a bare "pre-image" path string exists in the file
(`grep -n preimage scripts/cc-hooks/index-sync-post.sh` → the resolution line
and the two `$stashfile` uses only).

This file has no compose-stamp handling — that consumer is
`scripts/cc-hooks/index-compose.sh` (slice 4), out of scope here.

## Comment added

Added a comment above the (now keyed) resolution line explaining the key and
pointing to `index-sync-pre.sh` for the `agent_id`-vs-`agent_type` rationale,
rather than repeating it. No existing comment in this file was falsified by the
change: the file carried no comment asserting an invariant about which batch
"owns" the bare pre-image path (unlike `index-sync-pre.sh`'s "First
index-touching call…" comment, which slice 2's review had to rewrite) — the
closest comment, on the unconditional `rm -f`, already talks about bounding a
*stale* pre-image to a single batch, which stays true unchanged: the bound is
now per (agent, batch) rather than per batch, a strengthening, not a
falsification.

## Test results

Targeted:

```
$ bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats
1..2
ok 1 a parent post-hook leaves a subagent's pre-image intact
ok 2 the subagent's own post-hook then consumes its keyed pre-image
```

Full file:

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 71 passed, 0 failed
```

(70 pre-slice plus this slice's 1 previously-red case flipped; the other
previously-passing case stays green.)

`shellcheck -s bash scripts/cc-hooks/index-sync-post.sh` — exit 0.
`scripts/lint-shell.sh` — `lint-shell: 137 files clean`.

Whitespace: re-ran the targeted pair under `TMPDIR="/tmp/claude/space dir"` —
same 2/2 pass, so the keyed gitdir path surviving a space is exercised, not
assumed.

`git status --porcelain` before staging:
`M scripts/cc-hooks/index-sync-post.sh`, `M tests/index_sync.bats` (already
modified, not mine to touch further), plus the two untracked slice-3 reports and
the pre-existing ambient dotfiles.

## Gate verdict

Baseline sentinel before this change, confirmed by `cat`:

```
.git/gitlore/gates/lint             → 1006838979 1081834
.git/gitlore/gates/test-unit        → 1006838979 1081834
.git/gitlore/gates/test-integration → 1006838979 1081834
.git/gitlore/gates/check-distribution → 3914793056 496231
```

The gate was first run from this dispatch with `run_in_background: true` and its
verdict was **not** trusted: the three `precommit_inputs`-sharing sentinels
disagreed afterwards, `test-integration` holding a hash two bytes short of the
tree (`2975428467 1086122` against `1318920462 1086124`). That is the same
split-verdict symptom this run has now seen three times and it is still
unexplained — a background verdict is not evidence until it is.

Resolved by re-running in the **foreground**, from the orchestrating session:

```
$ just test-integration
bats: 72 passed, 0 failed
```

Then the three sentinels and an independent recomputation of `gate-inputs-hash`
over `precommit_inputs` were compared by hand and all four agree on the live
tree:

```
lint               2026-09-08 15:12:01  1318920462 1086124
test-unit          2026-09-08 15:28:16  1318920462 1086124
test-integration   2026-09-08 15:31:38  1318920462 1086124
recomputed live tree                    1318920462 1086124
```

`just precommit`, foreground, on that tree: `check-memory-hygiene` 90 facts / 0
errors, `check-docs-links` 49 decisions / 0 errors, `check-version` in sync
(0.7.1), and `lint` / `test-unit` / `test-integration` each
`cached (inputs unchanged)` — cached against the hash verified above, not
against an unknown one. Exit 0.

## Commit

Subject `Item 2.1/3 — the post-hook consumes the keyed pre-image` (the gitmoji
hook rewrites the `feat` prefix to `✨` on commit). Identified by subject, not
by sha: this report is *in* the commit, so any sha written here is the sha of a
tree that no longer exists once the report is amended in — which is how slice
2's report came to name a commit that is not in the log.

Carries `scripts/cc-hooks/index-sync-post.sh`, `tests/index_sync.bats` and this
slice's three reports.

## Consumers not touched

`scripts/lib/index-sync.sh` (slice 1's, unmodified), `index-sync-pre.sh` (slice
2, closed), `index-compose.sh` and `add-tier-batch.sh` (slice 4).
`tests/cc_hook_index_compose.bats` and `tests/cc_hook_add_tier.bats` untouched.
