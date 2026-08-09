## Brief: nothing owns `name:`, so filenames and slugs drift apart and break `[[links]]`

2026-07-30 — reported from `/Users/david/code/micro` (gitlore 0.4.3), after
mounting the `ddaanet` tier and routing 48 local facts up into it.

### What happened

The `ddaanet` tier now holds ~145 files under two incompatible naming
conventions: `feedback_foo_bar.md` / `reference_foo_bar.md` (snake_case with a
type prefix) alongside `foo-bar.md` (kebab, no prefix). **61 of the 145 have a
frontmatter `name:` that does not match their own filename** — usually kebab
name against snake filename, but a dozen are not slugs at all:

```
file=feedback_justfile_shebang_indent  name=justfile shebang recipes need consistent indentation
file=project_claude_plugin_dev         name=claude-plugin-dev toolkit
file=feedback_examine_evidence_drift   name=examine-evidence-for-drift-direction-don-t-assume-a-source-of-truth
```

The consequence is not cosmetic. A link author had two plausible spellings for
every target and no feedback about which was live, so **15 `[[wiki-links]]`
were silently broken** — `[[feedback-large-docs-review]]` pointing at
`feedback_large_docs_review.md`, `[[claude-plugin-dev]]` at
`project_claude_plugin_dev.md`. Two files had gone further and written the
index-style path inside link brackets:
`[[ddaanet/feedback_perf_fix_check_parallelism_assumption]]`. All 15 are now
repaired by hand in the consuming repo, and a normalization pass over the
filenames is underway — but the mechanism that produced them is untouched.

### Diagnostic

**gitlore already owns two of the three frontmatter fields and leaves the
third unmanaged.** `scripts/lib/index-sync.sh` both reads and *writes*
`description:` (`gitlore_get_frontmatter_description:33`,
`gitlore_set_frontmatter_description:53`), driving it from the index hook. It
reads `type:` (`gitlore_frontmatter_type:226`), tolerating both the indented
`metadata:` form and "the older top-level one". Nothing anywhere touches
`name:` — the sole `name:` hit under `scripts/` is an unrelated comment at
`util.sh:392`.

**The authoritative value already exists.** The index pointer path is what
`gitlore_compose_check_index` (`index-compose.sh:213`) validates for
uniqueness and what every composition path parses via `gitlore_bullet_path`.
`name:` is derivable from it by construction — the same derivation
`description:` already gets from the hook. The field is not hard to keep
correct; it is simply nobody's job.

**Claude Code's native memory guidance is unambiguous** and neither
convention in the tier follows it: basename == frontmatter `name:` == a short
kebab-case slug, with the category in `metadata.type` and *never* in the
filename. The `feedback_`/`reference_`/`project_` prefixes duplicate
`metadata.type` in the one place that also has to match link spellings.

**Tolerance is how it spread.** `gitlore_frontmatter_type` accommodating a
legacy top-level `type:` shows the same drift already happened once to a
different field and was absorbed rather than normalized.

### Requests

1. **Validate basename == `name:`** in `gitlore_compose_check_index`, beside
   the duplicate-pointer-path rule. It is the same class of check against the
   same authoritative path, and it is what makes the broken-link class
   impossible rather than merely unlucky.
2. **Sync `name:` from the pointer path** the way `description:` is synced
   from the hook, in `index-sync-post.sh`. The machinery is already there; it
   just stops one field short.
3. **Reject a type prefix in a pointer path**, and require `metadata.type` to
   be present. A `feedback_`-prefixed filename is a category duplicated into a
   namespace that must stay stable for links.
4. **Consider validating `[[link]]` resolution** at the same checkpoint —
   specifically a link in a *tier* file that resolves only to a root-local
   memory. Eleven such links existed here (`[[ghmem-project]]` and four
   others); they resolve in the repo that wrote them and are dead from every
   other consumer of the shared tier. That failure mode is invisible until
   someone reads the tier from a second repo.

### Constraints

- Investigation was read-only against `/Users/david/code/gitlore`; all edits
  were confined to `/Users/david/code/micro/memory/`.
- The 15 link repairs and the cross-tier link removals are already applied in
  micro and uncommitted there; the filename normalization is running
  separately. None of it depends on these requests landing.
- Counts above are from the tier as of this date and will move as the
  normalization pass completes.
