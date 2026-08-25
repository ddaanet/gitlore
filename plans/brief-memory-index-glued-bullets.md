## Brief: a glued MEMORY.md bullet validates clean and propagates into frontmatter

2026-07-29 — reported from `/Users/david/code/handoff` (gitlore 0.4.3 installed
cache)

### What happened

Two adjacent bullets in the project's root `memory/MEMORY.md` ended up joined
onto **one physical line**:

```
- [bats + shellcheck gotchas](ddaanet/reference_bats_shellcheck_gotchas.md) — …`# shellcheck` comment = directive- [git refuses ext:: by default](ddaanet/reference_git_ext_transport.md) — `fatal: transport 'ext' not allowed`; …
```

The index→frontmatter sync then wrote that entire line's tail — the second
bullet, markdown link and all — into the first memory's `description:`
frontmatter, and reported it as a routine replacement. The tier carrier
`memory/ddaanet/MEMORY.md` carried the same glued line after composition.
Repairing the root line and re-editing restored both; nothing is broken now.

### Diagnostic

**The sync is the amplifier, not the origin.** `gitlore_index_pairs`
(`scripts/lib/index-sync.sh:9`) is line-oriented awk: it splits on the *first*
`") — "` and takes everything after it as the hook. A glued line is one
syntactically valid pair whose hook happens to contain a second bullet, so the
sync faithfully copies it into `description:`. That is correct behaviour given
the input — but it turns one corrupt index line into a corrupt memory file,
where it is far less visible.

**Validation does not catch it.** `gitlore_compose_check_index`
(`scripts/lib/index-compose.sh:213`) tests duplicate pointer paths and
interleaved non-bullet lines. A glued line passes both: `gitlore_bullet_path`
matches the first `](…)`, so the line parses as a valid bullet for path 1 and
path 2 simply *disappears* from every parse of the index. That is the
data-loss path — with path 2 absent from `ours.paths`, the next compose reads
it as a root-side delete and drops it from the carrier.

**Origin not established** — *settled by the 2026-08-04 follow-up below: the
editing agent's own `Edit` call, reproduced on a fixture.* Ruled out:
pre-existing corruption (`HEAD:MEMORY.md` and two ancestors have zero glued
lines); the awk parser (line-oriented, cannot join); composition itself against
a copy of the store — inserting a new tier bullet mid-block and running
`gitlore_compose` on `$TMPDIR/…/memory` rewrote the carrier and left root
byte-identical, no glue. That copy had **no** `refs/gitlore/compose-base` (the
tier `.git` file pointed at the original gitdir), so the merge ran as a union;
the live store does have the ref, and the root-rewrite path under a real base is
the strongest remaining candidate. The other candidate is the editing agent's
own `Edit` call, which matters because the failure is self-reinforcing: `Edit`
is substring-based, so an `old_string` matching one bullet's text *inside* an
already-glued line splices new content mid-line and glues again.

### Requests

1. **Add a glued-bullet rule** to `gitlore_compose_check_index`: a line
   carrying a second `- [` after its first `](…) — `. It is the sibling of the
   two rules already there, and it is what makes the silent path-2 drop
   impossible rather than merely unlikely.
2. **Consider refusing to propagate** a hook containing `](` in
   `index-sync-post.sh`. A description that embeds a markdown link to a memory
   path is almost certainly a glue artifact, and the sync is where it escapes
   the index.
3. **Unrelated read-loop gap, found while reading:**
   `scripts/lib/index-compose.sh:342-348` reads the root index with
   `while IFS= read -r line; do … done < "$root"` — no `|| [ -n "$line" ]`
   guard, unlike `gitlore_index_region:91` and
   `gitlore_compose_check_index:217`. A root index whose final line lacks a
   trailing newline silently loses its last bullet from `ours`, which the merge
   reads as a root-side delete.

### Constraints

- Investigation was read-only against `/Users/david/code/gitlore`; the
  reproduction ran against a copy of the memory store under `$TMPDIR`.
- The reporting repo is `handoff`, whose only coupling to gitlore is the
  `gitlore.memoryApprovalClauseFile` config key and the two `.claude/`
  IPC filenames — nothing here depends on gitlore internals.

## Follow-up: origin established

2026-08-04 — second occurrence, reported from `/Users/david/code/micro`
(gitlore 0.4.5 installed cache). Same signature, independent incident.

### The origin is a Claude Code `Edit` defect

Deleting an index bullet by passing `old_string` as a **leading newline plus
the bullet text** with an **empty `new_string`** consumes the separator on
*both* sides of the match, welding the surrounding bullets into one line.
Reproduced directly on a `A\nX\nB\n` fixture:

| `old_string` | `new_string` | result | |
| --- | --- | --- | --- |
| `"X"` | `""` | `A\nB\n` | correct |
| `"X\n"` | `""` | `A\nB\n` | correct |
| `"\nX"` | `"\nY"` | `A\nY\nB\n` | correct |
| `"\nX"` | `""` | `AB\n` | **joins neighbours** |

Both conditions are required — empty `new_string` *and* a leading newline in
`old_string`. Substitution with the same leading newline is correct, so this is
the deletion path, not matching.

The mechanism follows from the bare-`X` case. `Edit` is line-oriented on
deletion: emptying a line removes the line rather than leaving it blank, which
is why `"X"` → `""` yields `A\nB\n` and not the naive `A\n\nB\n`. That
line-removal drops the line's *trailing* newline. When `old_string` has already
consumed the *leading* one, a single deleted line costs two separators. `Edit`
reports success identically in all four cases.

This confirms the second candidate above and, for this instance, exonerates
composition and the `refs/gitlore/compose-base` rewrite path: the glued line was
present in the root index as the direct result of the editing call, before any
compose ran.

### The predicted data-loss path was observed in the wild

The diagnostic above reasons that once path 2 disappears from every parse, the
next compose reads it as a root-side delete and drops it from the carrier. That
is exactly what happened. After the glue, `memory/ddaanet/MEMORY.md` had
`tier-routing-plugin-shaped` **deleted outright** while its neighbours appeared
joined — the entry was silently gone from the tier index while still present in
root. It was recovered only because the tier worktree was restored from its
merge commit.

So the glued-bullet rule is not defence in depth; it is the only thing standing
between a one-character edit accident and a silent index deletion.

### What this changes about the requests

**Request 1 (glued-bullet rule in `gitlore_compose_check_index`) — confirmed,
and the pattern stays simple.** Detect a second `- […](…) — ` occurring on a
line that already has one. Decision (2026-08-04): *no* backtick-awareness. A
hook has no legitimate use for a bare markdown hyperlink — the entry already
links its own file — so the pattern is safe by policy rather than by parsing.
Residual, accepted: a hook that backticks an index-format example would be split
spuriously. That is visible and repairable, and no such hook exists today —
checked across both live indexes, 102 entries, zero lines carrying a second
`](` or a second `- [` after the separator.

Rejected on the way there: a backreference form such as
`` [^`]+|(`+).+\1 `` for the middle segment. awk has no backreferences at all,
POSIX leaves them undefined in EREs, and the balanced-span version needs a lazy
quantifier that is PCRE-only — so it would force the check out of the awk idiom
the rest of the index parsing uses, to buy a guarantee the policy already gives.

**Request 2 (refuse to propagate a hook containing `](`) — confirmed by this
incident.** The sync wrote the two-bullet blob into
`ddaanet/gitlore-tier-merge-direction.md`'s `description:` and announced it as a
routine replacement. A description holding a second `](` and a second ` — ` is
structurally impossible as a hook, so rejecting it is cheap and independent of
whatever produced the glue.

**Request 4 (new): a `PreToolUse`/`PostToolUse` pair that repairs the edit and
reports its own obsolescence.** Decided 2026-08-13. A marker that only records
"something risky happened" leaves the corruption in place and leaves the agent
to infer, from a downstream check finding nothing, that the defect is gone.
Computing the intended result up front turns that inference into an observation
and a repair.

`PreToolUse` on `Edit` tests the argument shape alone — `new_string` empty,
`old_string` beginning with a newline. On a match it reads the target, computes
the intended result, and writes it to a temp file keyed by `session_id` plus
`file_path` (`PreToolUse` stdin carries no `tool_use_id`). `PostToolUse`
compares the file against that expectation and unlinks the temp file
unconditionally:

- **identical** — `Edit` no longer welds neighbours on this shape. Say so and
  count it; at a run of clean observations the pair and the glued-bullet rule
  both retire.
- **different** — write the expectation over the file. The join is undone at the
  edit site, before composition, the sync, or any pattern check sees it.

**Computing the intended result is three lines, not a reimplementation of
`Edit`.** For the risky shape, naive single-occurrence string replacement is
correct: `"A\nX\nB\n"` minus `"\nX"` is `"A\nB\n"`, the table's correct row. The
line-oriented deletion special case — emptying a line removes it rather than
leaving it blank — only applies when `old_string` carries no separator, and that
shape never reaches the branch. `replace_all: true` replaces every occurrence
under the same rule.

**Both output channels are load-bearing on the repair path.** `systemMessage`
carries one curt line so the human sees it. `updatedToolOutput` rewrites what
`Edit` reported, because the agent otherwise holds the corrupted diff as its
model of the file and edits against it; `additionalContext` alone leaves it
re-reading the file to check. `PostToolUse` cannot block, but it can write, and
the write is the whole point.

**Rejected: rewriting the arguments via `PreToolUse` `updatedInput`.** Moving
the leading newline from `old_string` into `new_string` sidesteps the defect
entirely and costs no temp file — and no divergence is ever observable again, so
the workaround can never be retired. The pair pays one file write per risky edit
to keep the observation.

**Scope: every `Edit`, not only index files.** The shape test is cheap and the
defect is not index-specific; narrowing to `MEMORY.md` would leave other files
silently welded and would starve the retirement signal of samples.

Requests 1 and 2 stand alongside it. The pair sees only glue that arrives
through `Edit`; a merge, a hand-edited carrier or a `Write` reaches the index
without passing it.

**Coverage note against a preimage-based design.** `index-sync-pre.sh:35-36`
takes its baseline only when the target is the root index or the tier manifest,
so tier *carrier* indexes have none — and hand-editing a carrier is a documented
requirement when a pointer arrives from upstream in a merge. Detection therefore
belongs in the stateless pattern check over root *and* carriers, not in a
preimage diff. The existing preimage remains useful as a cheap assertion where
it happens to exist.

### Upstream

The actual fix is a Claude Code `Edit` defect report. The four-case table above
reproduces it in about ten seconds and is self-contained.
