## Current task

Reviewing the commit that split `docs/design.md` (168.4 KB, 56.8 ktok) into a hub plus five reference nodes, first pass looking for essential information the split dropped.

A mechanical audit already ran — pre-split sentences diffed against the whole graph, misses ranked by how much of their distinctive vocabulary survives — finding 245 of 852 sentences rewritten, 12 under 85% coverage, and one genuine loss: a `bats -T` lead on NFR10's unmet gate, since restored. That audit sees verbatim loss only. What it cannot see is a hub conclusion that reads as settled but no longer resolves to the argument justifying it, or a mechanism paragraph made less accurate by being compressed into the hub's per-component summary — the Components section was rewritten, not moved, so it is the part no diff covers.
