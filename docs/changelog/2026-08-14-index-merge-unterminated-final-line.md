# 2026-08-14 — The divergence merge survives an unterminated final line too, on both the read and the concatenation

The same class as the day before, in `index-merge.sh` rather than
`index-compose.sh`: the entry-wise three-way merge that runs when a store
diverges, not the in-session projection. Found by reading the file after the
compose fix landed, then reproduced before anything was changed — both defects
are confirmed, neither was inferred.

`gitlore_index_merge_paths` read a side's bullets with a bare `read`.
`gitlore_index_part` passes a missing final newline through — `sed -n` prints
the last line as it found it — so an unterminated side lost its last path from
the list while the *bullets* file it is paired with still carried the line. That
asymmetry is what makes the loss silent: nothing downstream is missing a bullet
to notice. The presence rule reads the gap as a deletion. A path at base that
both sides still carry needs both to still list it, so one unterminated side
drops the entry; a path new since base needs one side to list it, so a side that
added an unterminated line adds nothing. In the reproduction all three sides
carried `b.md`, one of them unterminated, and the merge emitted `a.md` alone and
returned 0 — a clean merge that deleted a fact.

The concatenation had the mirror hazard the compose writer had. `git merge-file`
also passes a missing final newline through, verified directly rather than
assumed, so `cat out.pre out.bullets out.post` welded the first bullet onto an
unterminated preamble: `note appended by hand- [A](a.md) — hook`, again at exit
0. Reaching it takes a bulletless side — all preamble, emitted verbatim — whose
preamble edit wins the prose merge while another side contributes the bullets. A
freshly seeded tier carrier is bulletless by definition, which is the same shape
the writer's version of this had. The guard is the writer's: a separator only
when something follows, so a merge with nothing after the preamble still emits
exactly what it merged.

The other four bare reads in the file stay bare. They consume `git ls-files`,
`git ls-tree`, a heredoc and `gitlore_order_merge`'s `awk` output — producers
that terminate by construction, none of them a file a hand edit can reach. The
rule is about reading files other writers touch, and marking these would blur
which reads are load-bearing.

Three tests, red-checked against the unchanged code: the at-base deletion, the
new-since-base addition that never arrives, and the welded preamble. The first
two fail on different branches of the presence rule, so neither stands in for
the other.
