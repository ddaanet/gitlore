# 2026-07-29 — The memory-approval body became one paragraph per file, with a template, and the clause stopped being a sentence fragment

One line per changed memory file (D19, 2026-07-28) was the wrong unit. A memory
commit message exists to record what a fact now claims and what moved it; a line
holds the *what* and drops the *why*, leaving a body the diff already carries.
The clause now specifies a subject line, a blank line, then one paragraph per
file, each opening with a bold `**<Kind> <tier>/<slug>:**` prefix. The bold
prefix is not decoration: the approval prompt renders as a blockquote, and the
prefix is what lets the user scan a multi-paragraph body rather than read it.
The kinds — New, Update, Augment, Reduce, Remove — are unchanged. `MEMORY.md` is
excluded from the listing in the same pass: a paragraph per file makes an
index-line entry conspicuous, and it says nothing — the line moves with the fact
it points at, which the fact's own paragraph already reports.

The clause also ships a **literal template** of three example paragraphs, rather
than describing the shape in prose. Describing a form and having it inferred is
what the old wording did; a form that can be copied is reproduced accurately,
and the template is where the difference between New, Update and Remove (what
prompted it now / what changed and on what evidence / what showed it wrong) is
actually stated.

A template is multi-line, which broke the contract the file was built on: it had
been a mid-sentence fragment each of the four call sites spliced into its own
sentence. It is now a self-contained block appended **last**, and each site
moved its interpolation to the end. That forced one code change —
`scripts/cc-hooks/post-tool-use.sh` built its `additionalContext` JSON with a
heredoc, and a raw newline inside a hand-written JSON string is invalid, so the
hook now emits through `jq -n --arg` like every other hook here; that also
stopped `$mempath` and `$msgfile` from being interpolated into JSON unescaped.
The test consequence is the same fact from the other side: substring matches
against raw hook stdout stop working once the clause is escaped, so
`tests/cc_hook_post_tool_use.bats` and `tests/cc_hook_memory_commit_batch.bats`
decode `additionalContext`/`systemMessage` through `jq` before matching, and the
former also asserts the output parses as JSON at all. Four deliberate faults —
dropping the clause from each of the three arms, and reverting the hook to
hand-written JSON — each turned exactly the intended assertion red.

Not applied here: `handoff`'s `checkpoint_memory_directive` renders
`"…then a body with $clause."` and would print the block mid-sentence. Its own
tests use a fixture clause, so they stay green and only the live rendering
degrades; a patch moving `$clause` to a trailing block is proposed rather than
applied, since that repo is not gitlore's to edit.
