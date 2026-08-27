# 2026-08-27 — A prepared merge met by a later gate is continued, never aborted (FR13, D7, D24)

`stale-with-merge-head` — a state file *and* `MERGE_HEAD` in a store that a gate
or `/gitlore:resolve` walks — used to emit an `abort-then-retry` directive,
whose continuation ran `git merge --abort`, re-detached at the pending commit,
cleared the state file and the pin, and re-entered `resolve.sh` to prepare the
merge from scratch.

The premise was that a merge waiting across a session boundary is re-prepared
cheaply, which holds only while nothing has happened to it. Once the merger
sub-agent has run, the store holds a synthesis it wrote and staged — the
expensive part of the whole flow, and the one part no gate can recompute — and
nothing in the store tells that apart from a merge no one has touched. The
repair for a `MERGE_HEAD` that a checkout cleared already refused to abort for
exactly that reason, writing the pointers back and asking for
`continue-after-merge`; the branch beside it was still throwing the same tree
away.

The guard now emits `continue-after-merge` in both branches, and
`abort-then-retry` is gone: the subcommand arm, `load_continuation_state`'s
`abort` mode, the `pending` field only that arm read, and the tests that drove
it. Nothing is restored on the way — a store holding a state file and
`MERGE_HEAD` already sits exactly where `gitlore_prepare_merge` leaves one, so
the directive is the one a fresh preparation emits.

The trade is a merge whose authority moved while it waited: it lands against the
authority it was built on, and the continuation's own `push . HEAD:live` (or
`push origin live`, for a `head-vs-remote` merge) is then refused as a
non-fast-forward, which re-prepares against the current authority and yields
again. One extra cycle on a merge that outlived its session, against a
re-synthesis of every one of them — and aborting never protected against this
either, since it fixed the authority as of whenever the gate happened to run.

Three cases in `tests/resolve_recovery.bats` and one in
`tests/tier_divergence.bats`, each watched failing on the directive it asserts:
a gate meeting the prepared merge, the skill's standalone `resolve.sh` entry,
the continuation landing a merge prepared in an earlier session with the staged
synthesis in the commit, and a tier's merge continued in the tier while memory
stays clean. Each stages a file no auto-merge of the two sides produces, so what
the assertions read is the survival of the synthesis; the retiring continuation
was run against the same fixture first, and destroyed exactly that file.
`tests/resolve_merge_briefing.bats` keeps its "a re-prepared merge gets its own
briefing" case, driven now by the hand-run abort that kills a merge rather than
by the removed subcommand.
