# 2026-09-26 — Three briefs triaged, and the mount learns its own size

An inbox pass. Four briefs were checked against the tree rather than against
their own status lines; one had been overtaken entirely, one half-overtaken by
the `v0.8.0` release, and three findings were live.

**The `SessionStart` commit-protocol context says acts and nothing else.** It
carried an `(FR11)` id that resolves to nothing in the consumer repos it lands
in, spelled out the two command forms it forbids — inviting reasoning about the
forms it does not name — and described the machinery: what the gate is, which
hook blocks, what it records. None of that is actionable, and the gate states it
itself at the moment it fires. What remains is the prohibition, by role, and the
one-line happy path: never commit inside the memory submodule; writing a memory
file is an ordinary edit, and committing the parent repo is all it needs. The
absences are pinned in `tests/cc_hook_session_start.bats` — no `FR<n>`, no
`git -C`, no hook or gate mechanism — because each is a thing a later edit would
otherwise helpfully restore.

**`/gitlore:index-audit` now inspects the preamble.** Everything ahead of the
first pointer bullet is kept verbatim by composition, never mirrored into a tier
carrier, never checked for a dead path, and routes nothing — while the loader
pays for every byte. Past the scaffold's heading it is waste. The costly case is
a would-be entry that landed there, a bullet not opening with its link: it reads
as an index line, spends its bytes, routes nothing, and is invisible to a
`grep -c '^- \['` measure, so that count undercounts the very file the loader
truncates. A non-bullet line *inside* the block needs no step of its own —
`index-compose.sh` already reports it.

**A tier mount reports the size of the index it produced (D57).** Mounting is
the only operation that adds tens of KB in one step, and the only index-growing
path that is not a `PostToolBatch` pass over an index the agent edited, so D39's
byte-budget advisory never fired for it: a mount that landed at 25,846 bytes
reported the submodule, the scopes, the import line, the activation and the
recomposition, and left the session to discover by hand that its index was
truncating. `gitlore_index_mount_size_line` is measured after the mount hook's
own compose, since composition is what splices the tier's block in and any
earlier count describes a file the session never loads. Its loud arm names the
**loader cutoff** rather than a percentage of the advisory budget — the budget
(25,600) sits *above* the cutoff (~24,985), so a percentage reads as reassurance
in precisely the case where the mount has cost the repo its most specific
memory. `GITLORE_INDEX_LOADER_CUTOFF_BYTES` gives that empirical figure a home;
it is back-computed from the loader's own one-decimal `limit: 24.4KB` notice, so
it is approximate and never a refusal threshold. The line is keyed by no
once-per-episode marker: the intent file is consumed, so a mount reports once by
construction, and writing no `budget` marker leaves a later edit-time advisory
in the same session free to fire.

**What the tree had already answered.** The brief on index-edit propagation was
written against 0.7.1 and all three of its findings have since landed:
composition's report no longer claims it never changes a line's text, the
description sync writes that one line and stamps no `originSessionId` over
another session's provenance, and the pre-image is keyed by `agent_id` so a
subagent's edit propagates. The unlanded-merge sentence the merge skill was
missing shipped in `v0.8.0`.
