## Current task

Nothing is mid-flight — `.claude/handoff-todo.md` is the work. The context
the open decisions below need:

gitlore's `scripts/check-memory-hygiene.py` now carries a `volatile-state`
check for abbreviated commit ids in fact bodies. It matches
`\b[0-9a-f]{5,40}\b` read raw over bodies with frontmatter skipped, minus
all-digit runs and minus a closed 47-word list of a-f-spellable words
(alecjacobson.com/weblog/475.html). Over this store: 4 hits, 4 true
positives, 0 false. Stated residual — the all-digit exclusion costs
`(10/16)**7` of seven-character shas, about 4%.

The equivalent guard in `prohibitions@ddaanet`,
`deny-volatile-memory-state.sh`, scopes to full 40-hex shas and has
therefore never fired: the store holds no full sha, and four real commit
ids sat in fact bodies untouched. That repo is read-only, so
`/Users/david/code/prohibitions/brief-volatile-state-abbreviated-shas.md`
is the end of the involvement there. The other seven guards were probed in
both directions and behave as their headers document.

## Open decisions

- Does the memory-hygiene checker ship as part of gitlore, or stay a
  `scripts/` local? Shipping makes python3 + PyYAML user-facing.
  `volatile-state` is the first of its checks worth having in every repo
  that mounts a tier, which is what makes the question live.
- Tier-wide retirement of a ddaanet fact vs sub-scoping the mount. Byte
  pressure is off — the index sits near 24.1KB against the ~25.0KB loader
  cutoff, roughly five entries of headroom — so this is decidable on merit
  rather than under a deadline.