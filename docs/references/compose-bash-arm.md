# The compose trigger's `Bash` arm — the measurement behind D31

Why the mid-session compose trigger watches every `Bash` call and not only the
calls that name a memory file. The decision is D31, in
[index-composition.md](index-composition.md); this node holds the corpus
measurement and the timing it was settled on.

Watching `Bash` widens the `PreToolUse` matcher from calls that name a memory
file to every shell call, so the trade was settled against this machine's own
transcript corpus — 2,441 transcripts, 22,168 `Bash` calls, 13 months. Of those,
~49 mutated a real memory store: ~22 touched an index, ~29 a fact file, the sets
overlapping. All but one fall in the corpus's final five weeks, so the behaviour
is rising rather than a long-tail artifact — the arm earns more, not less, as
the store ages. Fifteen were `git checkout`/`git restore` and three `git rm` —
write paths that name no `file_path` at all, so no `Write|Edit` matcher can see
them however it is scoped, which is the part of the case that cannot be met
another way. Against 1,190 `Write`/`Edit` calls on memory files, the arm exists
for roughly 4% of the mutations and ~0.2% of the `Bash` calls it inspects. Of 25
native auto-memory stores under `~/.claude/projects/*/memory`, exactly one was
ever mutated from `Bash` across the whole corpus: shell mutation is a
*gitlore*-store phenomenon, because a gitlore store is a git repo the agent
already runs git against.

Cost, timed against this repo's real tree (23 KB index, one tier, 30–50 runs per
path, steady state): **~45 ms** on a `Bash` call once the batch has a baseline,
**~65 ms** on the first watched call of a batch (two `cksum`s plus the index
`cp`), against ~18 ms for the bare unwatched-tool exit; a cold page cache
roughly doubles all three. That is ~45 ms on every shell call to catch a
mutation in one call out of five hundred. Accepted, because the failure it
prevents is silent — the edit lands, neither propagation nor composition runs,
and the store desyncs with nothing to show for it — and 45 ms is invisible next
to a tool call's own latency.
