# 2026-10-15 — A clone on rewritten history is refused, not merged back

**A rewritten store publishes a rewrite record (D61).** `gitlore/rewrites` on
the store's remote holds `version` (`1`) and a flat `map` of `<old> <new>`
lines, changed ids only, appended per rewrite. `scripts/record-rewrite.sh`
writes it from filter-repo's `commit-map` on the rewritten mirror, before the
force-push; the old tip goes on a separate archive branch that no gitlore fetch
names. The trigger is the ddaanet identity rewrite: to every ancestry-reading
gate, a clone still on the old history looked like an ordinary divergence, and
`gitlore_yield_merge` prepared a clean merge that the next push would publish,
doubling the history.

**A divergence on recorded old history is refused (D62).** A yield against the
remote's `live` fetches the record by explicit refspec and refuses when a commit
in `authority..pending` is a recorded old id, before the merge marker is
written, so a refusal leaves nothing for the next gate. An absent record
proceeds; one that exists but cannot be fetched refuses. A yield against the
local `live` skips the check and stays offline: old history reaches the remote
only through a yield against the remote's `live`, which takes the check.
SessionStart's divergence report takes the same test for memory and each tier,
naming the crossing instead of `/gitlore:merge`.

**Crossing is a manual script.** `scripts/cross-rewrite.sh <store>` maps `HEAD`,
`live` and `main` through the record's chains, checks each new tree against the
old one modulo gitlinks (mapped through the child's own record), moves nothing
until every ref passes, and stages the store's gitlink in its parent. Local
commits on old history are refused with the commands that replay them; a store
already on the new history has nothing to cross. No automatic crossing, no
parent-repository guard.
