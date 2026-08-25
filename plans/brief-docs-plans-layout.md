## Brief: adopt the docs/ + plans/ documentation layout

2026-07-29

`claude-plugin-dev` reorganised its documentation on 2026-07-29 and the shape
should propagate to every plugin repo in this family (handoff, gitmoji,
onekeys, cwd-safety, shell-gotchas, gitlore). This brief is dropped identically
into each; the target layout is the same everywhere, only the starting state
differs.

### Decisions

- **`docs/` holds only what is true now.** Two files plus one directory:
  - `docs/design.md` — the living rationale for every design decision. Present
    tense. When a decision is overturned it is *rewritten in place* with the new
    reasoning. Never struck through, never annotated with "formerly".
  - `docs/changelog.md` — an index, newest first, one line per entry:
    `- [YYYY-MM-DD — Title](changelog/YYYY-MM-DD-slug.md) — one-line hook (vX.Y.Z)`
  - `docs/changelog/YYYY-MM-DD-slug.md` — the write-time record of one change:
    what moved, and the reasoning available at the time. **Never revised** — a
    dated record is correct forever precisely because it is dated.
- **`plans/` at the repo root holds prospective content**: specs, design
  proposals, implementation plans. Anything describing work not yet done, or
  describing how something was built rather than what it is.
- **Root `DESIGN.md` goes away**, split into `docs/design.md` (the timeless
  part) and a set of dated changelog entries (the historical part). In
  claude-plugin-dev this cut an 80-line file down and produced six backfilled
  entries from the git history.
- **`docs/superpowers/{specs,plans}/` goes away**, contents moved to `plans/`.
  The `superpowers/` nesting was an artifact of which skill generated the file,
  which is not a property worth encoding in a path.
- **`CLAUDE.md` must be updated in the same commit** — its Layout section names
  these paths, and a stale path there misdirects every future session.

### Constraints

- The date in a changelog filename is **the day the record is written**, not the
  day the change shipped. Backfilled entries are dated the day of backfill only
  if no better date exists; prefer the date of the commit being recorded.
- The version, when there is one, goes in the `changelog.md` pointer line, not
  in the filename.
- Use `git mv` so history follows the file. `DESIGN.md => docs/design.md` should
  show as a rename in `git show --stat`, not as a delete plus an add.
- Every in-repo reference to the moved paths must be fixed: `README.md`,
  `CLAUDE.md`, `justfile` recipes, scripts, and any `memory/` note that cites a
  path. Grep for `DESIGN.md` and `docs/superpowers` before declaring done.
- Do **not** touch `plugin-dev/` — it is a vendored `git subtree` of
  claude-plugin-dev. Changes there are made upstream and pulled in via
  `just update-plugin-dev`.
- This migration is **independent of the plugin-dev 0.5.0 propagation**. Neither
  blocks the other; sequence them however is convenient.

### Rejected approaches

- **Keeping a single root `DESIGN.md`.** It accumulated two incompatible kinds
  of content: the current design, which wants rewriting in place, and the
  history of how it got there, which must never be rewritten. Editing either one
  in a shared file risks corrupting the other.
- **Dating changelog entries by release.** Entries do not map one-to-one onto
  releases — one release can carry several decisions, and some decisions ship
  across two. The write date is unambiguous and needs no reconciliation.
- **A single `docs/changelog.md` containing all bodies.** It grows without bound
  and every append rewrites a file that is supposed to be immutable per-entry.
  The index-plus-bodies split keeps each record independently frozen.

### Additional context

Reference implementation: `/Users/david/code/claude-plugin-dev` — see
`docs/changelog.md` for the index format, `docs/design.md` for the present-tense
voice, and `CLAUDE.md`'s "Layout" and "Conventions" sections for how the rules
are stated to future agents. The two commits are `c37f3cb` (split DESIGN.md) and
`1c9999c` (specs to plans/).

Per-repo starting states as of 2026-07-29:

- **handoff** — root `DESIGN.md`; `docs/changelog.md` + `docs/changelog/`
  already exist and already follow the convention; `plans/` already exists.
  Loose design docs sit directly in `docs/`
  (`2026-07-18-precompact-drive-design.md` and three others) — those are
  prospective and belong in `plans/`. Also has a `docs/superpowers/` tree.
- **gitmoji** — root `DESIGN.md`; `docs/superpowers/{specs,plans}`; one loose
  `docs/2026-07-27-sessionstart-message-brief.md`. No changelog yet.
- **onekeys** — root `DESIGN.md`; `docs/superpowers/{specs,plans}`. No changelog
  yet.
- **cwd-safety** — root `DESIGN.md`; `docs/superpowers/{specs,plans}`; `plans/`
  already exists.
- **shell-gotchas** — root `DESIGN.md` only, no `docs/` at all. The lightest
  case: create `docs/design.md`, and add a changelog only if there is history
  worth recording.
- **gitlore** — furthest along: already has `docs/design.md` and
  `docs/changelog.md`, no root `DESIGN.md`. Remaining work is moving
  `docs/plans/` and `docs/superpowers/{specs,plans}` to a root `plans/`, and
  deciding where `docs/references/` belongs (it is current reference material,
  so `docs/` is right — leave it).

Incidental: several `docs/` trees carry `.DS_Store` and `._*` AppleDouble files
that were committed by accident. Clean them up and add the ignores while moving
things, but in a separate commit.
