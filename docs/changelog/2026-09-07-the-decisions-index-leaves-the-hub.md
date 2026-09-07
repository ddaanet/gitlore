# 2026-09-07 — The decisions index leaves the hub

`docs/design.md` reached the 400-line cap `scripts/check-docs-links.py` puts on
every file under `docs/`, with a new decision waiting to be concluded in it. The
alternatives were a separate, higher cap for the hub — argued as "the hub is
read whole, so a node's budget does not apply" — or a further split. The split
won: the cap's own docstring prefers it, and the hub had a seam that a size
argument had hidden.

The seam is need-time. Everything above `## Design Decisions` says what the
system is and how it is built, read while building or debugging a component.
Everything below it is the argument index, read whole when weighing or adding a
decision. That boundary falls on a section heading, so the decision groups and
their *Rejected* lines move verbatim into `docs/decisions.md`, and the hub keeps
its six sections with §Design Decisions and §Rejected Alternatives as pointer
stubs, the shape §Changelog already had toward `changelog.md`.

The checker follows the conclusions: every conclusion line and every delegation
is read from the decisions index, a missing index is an error like a missing
hub, and citations in the hub are still checked against what the index and the
nodes define. Nothing needs a conclusion in both files, so there is no two-file
hub — one constant moved. The 400-line cap stays uniform.

The same pass collapses the hub's two install-time sections, Hook Manager
Support and Remote Repository, into one short Install-time surfaces paragraph.
Both restated what `docs/references/installation.md` already holds rather than
summarizing it, and both are read when changing `/gitlore:install`, not when
reasoning about memory. The hub goes from 400 lines to under 280 and the
decisions index starts near 130.
