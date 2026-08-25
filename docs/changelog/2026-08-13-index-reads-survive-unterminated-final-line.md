# 2026-08-13 — Every index read survives an unterminated final line, and the writer stops welding a bullet onto an unterminated preamble

Confirmed data loss, found from `edify` and reproduced end to end. That store's
`memory/ddaanet/MEMORY.md` silently lost its last pointer line; the loss
surfaced only because it blocked an unrelated commit at the FR11 gate. Recovery
there was a checkout — HEAD still had the line — but the file was still
unterminated at HEAD, so the next pass would have dropped it again.

A bare `while IFS= read -r line` fills `$line` and *then* returns non-zero at
EOF, so an index whose last line carries no newline has that line read and
discarded. `gitlore_compose_down` builds three path lists — root at HEAD, root's
working tree, the carrier — and merges their order. An unterminated carrier is
missing its last path while base and ours both carry it, which
`gitlore_order_merge` reads as *theirs deleted it*: the path leaves the merged
order entirely, and the loop that emits only paths present in that order never
reaches the branch that would have taken root's copy. Two severities, and the
milder one is the quieter: carrier unterminated and root terminated loses the
line from the carrier alone, which `gitlore_compose_orphans` cannot report
because the orphan check runs the other direction. Both unterminated loses it
from *both* indexes in one pass, leaving the fact file on disk with no pointer
on any surface.

`index-compose.sh` already guarded two of its fifteen index reads —
`gitlore_index_region` and `gitlore_compose_check_index` — and that
inconsistency *was* the bug: the region arithmetic counted a line the projection
could not see. All fifteen carry the guard now, including the reads whose loss
has no visible symptom today, and the file header says why so the next read
added to it is not the sixteenth exception.

Normalising the file on write was rejected as the fix. `gitlore_compose_write`
already terminates its own output, which is why the damage is exactly one line
per unterminated commit rather than progressive — so fixing the writer fixes
nothing about the reads. The unterminated files are precisely the ones gitlore
did not write: hand edits, agent `Edit` calls, and carriers another consumer
committed that way. Treating it as a `gitlore_order_merge` bug was rejected on
the same evidence: the merge behaves correctly given its inputs, and is fed a
list that already lost the path.

Verifying that turned up an adjacent defect in the writer after all, in the one
case the termination argument does not cover. A bulletless index is *all*
preamble, emitted verbatim, so a bulletless index that arrived unterminated took
the first composed bullet onto the end of its last line —
`# Tier index- [A](a.md) — x`. A glued line does not parse as a bullet, so the
pointer is lost on write exactly as the unguarded reads lost it on read, and a
freshly seeded carrier is bulletless by definition. The write now emits a
separator when, and only when, there are bullets to separate; with nothing to
write the file is left byte-identical, which a second test pins so the separator
cannot grow into normalisation.

Five tests. The two `gitlore_compose` regressions use a new `unterminate_index`
fixture helper — every `seed_*` helper appends with `printf -- '…\n'`, so
nothing else could reach the state — and it asserts its own result, since a
silently no-op helper would make both tests pass whatever the code does. They
assert the exact bullet block on *both* indexes, so the carrier-only severity
and the both-surfaces one fail independently, and the root assertion pins which
surface the loss lands on. A third covers the dangling report, whose scan is a
separate read. Red-checked before the fix: all three failed on the dropped line,
and the writer's on the glued one.
