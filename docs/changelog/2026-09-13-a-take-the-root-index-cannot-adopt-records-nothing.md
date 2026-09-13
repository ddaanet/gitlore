# 2026-09-13 — A take the root index cannot adopt records nothing (D50)

When `gitlore_compose_up` refused a tier take, `gitlore_adopt_tier_into_root`
reported it and then staged and committed the moved gitlink anyway. That put the
tier back on its pin while root still held the tier's older block. The printed
remedy — fix the store, edit `MEMORY.md` to retrigger composition — then ran a
down projection that wrote root's older text over the carrier's newer line, and
`gitlore_compose` exited 0. The deliverable review of `index-edit-propagation`
flagged the disagreement with D50 (finding M5), and a probe reproduced the
overwrite with a real duplicate-pointer refusal.

A failed up projection now stages nothing, commits nothing, and checks the tier
out at its pre-take commit. The take exits 1. The arrival stays in the tier's
local `live`, the state `gitlore_adopt_advanced_live` adopts, so the remedy is
to fix the store and run `/gitlore:merge` again, which retries the whole
adoption.

Staging nothing without the walk-back, as `gitlore_adopt_recovered_merge` does
inside a gate, was weighed. On the take path it leaves the tier ahead of an
unstaged pin. The pin guard then refuses every memory commit with a
hand-adoption remedy until `SessionStart` walks the tier back, and a take in
that window finds the remote contained in HEAD and reports nothing to take.
Walking back at once reaches the same resting state without the window. The
checkout cannot lose work: a take refuses a dirty tier, and the up projection
writes only the root index.
