# 2026-08-26 — The down projection refuses a tier that was moved off its pin (FR15, D31, D36)

Observed in a real session. An agent ran
`git -C memory/ddaanet reset --hard origin/live` by hand, which took the tier
past the gitlink the memory store records for it without going through
`/gitlore:merge` — so no up-projection ever adopted the carrier's newer text
into the root index. An unrelated `Edit` to the root index then fired the
`PostToolBatch` recompose, the down projection ran with root as canonical, and
root's older wording for two tier lines was written over the carrier. The pass
reported a successful compose. What it had done was overwrite approved upstream
text with text nothing upstream had ever seen.

D36 is what makes the down projection safe without a base: the root's tier block
and the carrier are two projections of the same facts, and
**only one of them can move between passes** — the agent edits the root, the
carrier moves only when a merge lands. The pin is the whole reason that holds,
and composition never checked that the tier was still sitting on it. The
assumption was load-bearing and unenforced, which is the shape a silent data
loss takes.

`gitlore_compose_check_pins` enforces it. For each **active** tier that is
materialized, the tier's `HEAD` is compared against the gitlink the memory
store's **index** records (`git -C <mempath> rev-parse -q --verify :<tier>`); a
mismatch is one problem line and the pass writes nothing, exactly as the other
refusals do. The index rather than `HEAD:<tier>` because the index is the pin
`submodule update` actually reads, and every path that advances a tier stages
the moved gitlink there as its last act (D43) — reading `HEAD` would call a
landed merge a defect for as long as the memory commit recording it is pending.
Staging the gitlink is therefore also the fix, and it is the same hand-off the
merge paths already perform: `git -C <mempath> add -- <tier>` makes the store
compose again.

The rule is the **down pass's alone**, which is why it lives outside
`gitlore_compose_check` and only `gitlore_compose` calls it.
`gitlore_compose_up` is the adoption step of a landed merge, and it runs while
the tier is legitimately ahead of the pin — before the merge path stages the
move. A parameter on the shared check would have left the merge path one
argument away from refusing the state it exists to land; a function the up path
never calls makes the scope structural instead of conditional.

Two wordings, because two states need different remedies. A tier that is
mid-merge — a state file, or a `MERGE_HEAD` — is sent to `/gitlore:resolve`:
the return-to-the-pin checkout would unlink `MERGE_HEAD` and destroy the
prepared merge. Anything else gets the checkout, with the tier's absolute path
and the pinned sha in full so the printed command runs verbatim. The mid-merge
predicate is `gitlore_detect_stale_merge_state`'s own "not clean" spelled out
rather than called, because that function lives in `resolve.sh` and `resolve.sh`
sources `index-compose.sh`.

The rule found a second, latent instance of the same defect on the way in.
`/gitlore:add-tier` mounts with `submodule add`, which records the remote's
**default** branch, and then detaches the tier at `live` — advancing it past the
gitlink it just staged, and composing in the same batch without re-staging. So a
mount already met D43's silent revert: the next `SessionStart` would walk the
fresh tier back to the default branch while the root index composed from the
`live` carrier survived to describe facts the tier no longer held. The mount is
an advancing path and now stages the gitlink like every other one, which is also
what keeps the new refusal from firing on a perfectly good mount.

`SessionStart` meets both notices at once: its tier loop skips a mid-merge tier
without pinning it, and the compose that follows refuses on the same tier.
Refusing there is right — projecting root's index onto a carrier holding a
staged merge would dirty the merge — so the two notices are made to name one
remedy, and `tests/tier_divergence.bats` asserts that the message carries
`/gitlore:resolve` and never the checkout.

Six cases in `tests/index_compose.bats`, each watched failing against the
unchanged code first: the refusal and the commands it prints, the two mid-merge
shapes (with `MERGE_HEAD` and with a state file alone), and the staged-gitlink
recovery. Two are exclusions rather than reds — adoption still running with the
tier ahead of its pin, and a dormant tier's position not being this rule's
business — so each was checked against the mutation it exists to catch: moving
the rule into the shared check reds the first, and keying it on mounted rather
than active tiers reds the second.
