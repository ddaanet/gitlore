---
description: Curate the always-loaded memory index store-wide — measure it against the loader cap, relocate, retire or merge entries, then audit the diff for lost routing. Run when a session reports that only part of MEMORY.md was loaded, or on a deliberate curation pass. Not for a single fact — that is the memory-writing skill.
allowed-tools: ["Bash", "Read", "Edit", "Write", "Agent"]
---

# /gitlore:index-audit

The root `memory/MEMORY.md` is loaded verbatim into every session, and it has
a hard cap: past roughly 24,985 bytes (24.4 KB) Claude Code silently truncates
the tail and says so once (`MEMORY.md is 25.8KB (limit: 24.4KB) — Only part of
it was loaded`). gitlore's own check (`GITLORE_INDEX_BUDGET_BYTES`, 25,600,
warning at 80%) reports and never refuses. Composition puts tier blocks first
and the project's own lines last, so what falls off is the repo's most specific
memory. The index is O(N) against a fixed cap — at a disciplined ~180 B per
line it binds near 139 facts — so this pass recurs; it is a decision about
what the store should still contain, not a byte-shaving exercise.

## 1. Measure

```
wc -c memory/MEMORY.md
awk '{ print length, $0 }' memory/MEMORY.md | sort -rn | head -10 | cut -c1-120
```

Cost is bytes, not lines. The longest entries are where curation pays: five
paragraph-length lines can be a fifth of the blob while every terse line
together is a rounding error.

## 2. Choose the lever

Three levers buy real headroom; two things that look like levers are not.

- **Relocate the acted-inline class.** A line with no lookup step — what
  model to name, how to answer a correction, what belongs in always-on
  context — was never index material. Move it to `CLAUDE.md` or the tier's
  conventions file, **whole, with its carve-outs**: read the fact's "how to
  apply", not just its line, because the exceptions live there and a rule
  that lost one is wrong in a place nothing routes past. Measured once: 24
  lines out freed 3,491 B, the largest lever available.
- **Retire.** The only lever that removes bytes, because a fact's triggers go
  with it. Verify the premise: "that workstream is finished" needs checking
  against what still ships — six facts once went out as a closed probe while
  two skills built on them were live. A retirement inverts the audit in §4:
  the literals are supposed to fall to zero, so the question is whether one
  falls to a single occurrence on an unrelated line.
- **Merge for routing** — two entries competing on one trigger hand an agent
  half a rule. Never for headroom: the merged line must still carry both
  entries' literals, so three merges measured 39 B net and one left the index
  larger.

Not levers: **trimming lines** — a 32,405 → 24,316 B trim produced 58 audit
findings (misroutes, tokens at zero, rules that lost their exception, one line
rewritten into a false claim) and the repairs consumed almost all 8 KB it
bought, because prescriptions carry trigger literals and carve-outs live in
the prescription half; and **rewriting fact bodies** — applying the writing
rules to a sample moved the files 2% and the index by exactly zero, since the
two govern different surfaces.

Edit the root `memory/MEMORY.md` only. Tier carriers and every touched file's
`description:` follow from that edit.

## 3. Sweep the vocabulary before and after

Capture the pre-edit index before touching it, then compare word sets after
every batch of edits. Sweep plain words, not just backticked spans — bare
identifiers (`heredoc`, `precompact`, `mtime`, a model name) carry routing
weight without markup, and a backtick-only sweep once reported zero misroutes
where the plain-word sweep found four.

```
git -C memory show HEAD:MEMORY.md | tr -s '[:space:]' '\n' | sort -u > "${TMPDIR:-/tmp}/index-before"
tr -s '[:space:]' '\n' < memory/MEMORY.md | sort -u > "${TMPDIR:-/tmp}/index-after"
comm -23 "${TMPDIR:-/tmp}/index-before" "${TMPDIR:-/tmp}/index-after"
```

Every word printed is lost from the index. For each distinctive one, count its
lines before and after (`grep -c -F -- "<word>"`). Two failure grades:

- a token at **zero** — the memory is unreachable by that route;
- a token at **one, on a different line** — worse than deletion, because the
  survivor now misroutes: `index.lock` left only on a sandbox entry sends an
  agent hitting it inside a git hook to the wrong diagnosis.

A trigger that went missing in an unrelated earlier commit with no mention in
its message is not a divergence to weigh — restore it.

## 4. Dispatch two adversarial auditors

Self-review does not catch this: the author knows what each line means and
reads the trimmed version as adequate. Two auditors on different briefs find
disjoint classes (33 and 25 findings with little overlap, measured once).
Dispatch both against the diff, each briefed to falsify rather than confirm,
each writing to its own output file and replying with one line naming it.

**Brief A — trigger loss.** Given `git -C memory diff HEAD -- MEMORY.md` and
the two word lists from §3, falsify the claim that only elaboration was cut.
Report every literal that fell to zero; every literal now present on exactly
one line that points at a different fact than before; every line where a
condition was cut and a prescription kept; every collapsed disambiguation
("X vs Y" reduced to one side); every hook that now names a count rather than
a thing. When done, re-verify each finding against the AFTER text before
reporting, and re-read the diff once more for what the first pass missed.

**Brief B — meaning damage.** Given the same diff and read access to every
fact file a changed line points at, falsify the claim that every changed line
still says what its file says. Report every rule that lost an exception or
carve-out its file states; every inversion by truncation; every neutral
"X vs Y" that no longer says which side the memory lands on; every scope drift
(a rule now broader or narrower than its file); every line whose claim is now
false against its file. Same self-verification before reporting.

Read the two files, not the replies. Repair each confirmed finding in the
index line, not the fact file.

## 5. Review the whole submodule diff

Editing the index rewrites the `description:` of every fact file a changed
line points at, so a two-line index edit can produce a fifty-file diff. Review
`git -C memory status --short` and the frontmatter changes as part of the
pass, then let the change ride an ordinary parent commit — the pre-commit hook
gates it. Report the before and after byte counts, the levers used, and the
auditors' confirmed findings with their repairs.
