## Brief: two doc gaps met from edify — preamble lines in index-audit, unlanded merges in merge

2026-09-15

Found in `ddaanet/edify` while curating memory. Both began as candidate
memory facts and were deleted as owned by gitlore, not by any memory store.
Checked against gitlore `main` on the date above.

### Decisions

- **(a) is open.** `/gitlore:index-audit` (`commands/index-audit.md`) should
  say that a line ahead of the first pointer bullet is invisible to
  composition yet still paid for by the loader.
- **(b) needs only a release.** `skills/merge/SKILL.md` step 2 on `main`
  already says the same store returning the same prepared block is an
  unlanded merge, to be continued and never discarded. That sentence landed
  after `v0.7.1`, and the installed 0.7.1 merge skill lacks it. Nothing to
  write, but the next release carries a fix a live consumer needs.
- One brief for both, because they came from the same pass.

### Constraints

- Written from another repo, so this is input and not a scheduled change.
  Wording and placement are the gitlore session's call.
- The hook's loud half of (a) already exists. `index-compose.sh` prints
  `interleaved non-bullet line N inside the pointer block` with its remedy.
  Only the quiet half is missing.

### Rejected approaches

- **Keeping either as a memory fact.** Both reduce to "when running this
  gitlore procedure, know X", so the procedure is their owner. The edify
  root index is also over the loader cutoff, so a fact there would cost
  bytes nobody reads.
- **A new hook warning for (a).** A leading `# Memory Index` heading and
  prose preamble are legitimate, so a line there cannot be flagged
  mechanically as a mistake. The judgement belongs to the audit pass.

### Additional context

**(a) mechanism.** `gitlore_index_region` defines the pointer block as the
span from the first to the last line `gitlore_bullet_path` recognizes, which
is a plain link-first bullet. Everything before it is preamble, which
`gitlore_index_part` keeps verbatim. So a would-be index line ahead of the
block, such as a bullet that does not open with its link, composes cleanly
and:

- is never mirrored into a tier carrier and never checked for a dead path,
- routes nothing to a fact through gitlore's tooling,
- still counts toward the Claude Code loader cutoff, and
- is missed by any pointer-count measure such as `grep '^- \['`, so that
  count undercounts the file the loader truncates. The ddaanet tier fact
  `gitlore-tier-index-budget.md` recommends exactly that grep.

Index-audit's own step 1 measures `wc -c` over the whole file, so the audit
itself does not undercount. The gap is that no step tells the auditor to
inspect the preamble: convert a stray index line to pointer form or move it
out.

**(b) mechanism, for the release note.** The merger subagent can return a
correct staged synthesis with `MERGE_HEAD` still set. Re-running reconcile
then prints the same "memory merge prepared" block for the same store, which
reads as a second divergence. Only `resolve.sh continue-after-merge` lands
it.
