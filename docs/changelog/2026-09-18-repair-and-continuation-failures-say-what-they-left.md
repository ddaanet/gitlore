# 2026-09-18 — Repair and continuation failures say what they left (D52)

The deliverable review of the arrival repair (D52) found its failure paths
reporting less than they knew. A repair that walked back on a transient failure
printed none of the refusal, and one that could not fix the carrier printed only
the carrier's problems. The transient failures closed with
`Fix the store, then run /gitlore:merge again.` though the store was not what
needed fixing, and every walk-back said the tier's local `live` kept what
arrived, even where it held the repair. A transient failure — the scratch
directory, a read, the rewrite, the commit build, the `live` advance, the
checkout that follows — now prints its own failure line, the full refusal under
`gitlore: the root index could not take tier '<t>''s lines:`, and
`Run /gitlore:merge again.`, because the next take repairs from scratch. An
arrival the repair cannot fix lists the refusal's other lines under the same
header and, when there are any, names both fixes. The walk-back says `live`
keeps the repair once it does.

The scratch copy of the carrier moves from the tier's gitdir to a `mktemp -d`
directory under `$TMPDIR`, so a killed take leaves nothing in a repository.

A take run mid-loop in `gitlore_push_stores` could repair a tier whose own
iteration had already pushed, and memory's push then recorded a gitlink that
tier's remote lacked. One pass after the tier loop, before memory's push, now
pushes every tier whose `live` is not an ancestor of its `origin/live`. A tier
push that fails is reported by one reporter, which keeps the moved-remote
wording for a divergence refusal and says `not because of divergence` otherwise.

`gitlore_repair_index` leaves its output unterminated only when the input's own
unterminated last line is still last. Dropping an unterminated last line, or
moving strays after an unterminated last bullet, used to print the line that
became last without the newline it had.

A merge continuation's exits before its merge commit now say what they leave: a
message file that cannot be created, a message that cannot be built and a
refused merge commit each print
`… so the merge was not committed; the merge stays prepared.` The merger and the
resolve skill key on exit status rather than on that phrase: only exit 0 is a
landed merge, the named lines route to a re-synthesis, **Summarize** or
**Loop**, and any other non-zero outcome is reported as unrecognised. A
deny-list on the phrase would have read every exit with no `gitlore:` line — an
errexit abort on a malformed state file, a failed staging command — as a landed
merge.

The tests behind the earlier change gained the assertions the review found
missing, each proven against a mutant.
