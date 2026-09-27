# 2026-09-26 — A tier's prepared merge outranks the screens too

The prior fix ordered a prepared merge ahead of the summary screens on both
commit entry points, but every one of its tests read `gitlore_store_mid_merge`
against the root store only. `gitlore_sync_tiers_to_live` prepares a
head-vs-live merge inside the *tier's own* gitdir, not the root's, so a tier
mid-merge left the root store holding no merge of its own — dirty, as every one
of these screens requires, but reading not-mid-merge — and all three answered
wrongly: `memory-commit-batch.sh`'s post-run screen fell to the freshness arm
and dropped the merge directive it already held; its pre-run screen asked for a
summary over a merge both of whose sides were already approved (D49); and
`commit-memory.sh`'s own guard passed silently through to its "Pass it with -m"
refusal. All three self-healed — the next batch or a fixed retry caught up — but
each cost a wasted approval turn on content the guard would refuse anyway.

`gitlore_any_store_mid_merge` (`scripts/lib/util.sh`) composes
`gitlore_store_mid_merge` over the root and every mounted tier, mirroring the
tier loops `resolve-sync-memory.sh` already runs. Both mid-merge reads in
`memory-commit-batch.sh` take it, and `commit-memory.sh` gains its own tier loop
over `gitlore_guard_stale_merge_state`, inside the no-approval arm the loop
exists to outrank — the guard, not the predicate, because it is what emits the
directive these paths must hand over. `gitlore_store_mid_merge` stays:
`index-compose-check.sh` asks about one named store and must keep doing so.

The usage string also picked up the bare invocation it never listed, even though
it is the form the batch hook always calls.
