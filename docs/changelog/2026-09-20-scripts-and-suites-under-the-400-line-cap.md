# 2026-09-20 — Every script and bats suite on the split list sits under the 400-line cap, by pure moves

The 400-line cap was adopted for `docs/` on 2026-08-25, on an argument about
what a reader takes in at one go. That argument is not about markdown.
`scripts/lib/resolve.sh` stood at 2084 lines and `scripts/lib/index-compose.sh`
at 766 — files nobody reads whole, and so files where a function's neighbours
stop telling you anything. The cap extends to shell scripts and bats suites.

Nineteen splits, all pure moves. `lib/resolve.sh`, `lib/index-compose.sh`,
`lib/index-sync.sh` and `lib/util.sh` stay the files callers source, and pull in
function-only sibling parts — ten `resolve-*.sh` siblings among them — so no
call site changed; `scripts/resolve.sh` keeps its gates and sources its
continuation functions from `lib/continuation.sh`. Fifteen bats suites are cut
along their own section banners, with shared setup moving to `tests/helpers/`;
the publication sections of `push_behind_vs_diverged` go to
`push_tier_publication`.

What makes a pure move checkable is that it is checkable: function bodies are
byte-identical under `declare -f`, every `@test` name is preserved, comments
naming a moved function or test point at its new file, and the
rejection-discriminator site list names each part that now carries the pattern.
Per-split reports and the agent brief are in `plans/file-splits/`.

The cap outside `docs/` is a convention rather than a gate: the `oversized-file`
check in `scripts/check-docs-links.py` covers `docs/` only, so nothing will
notice when a script crosses 400 lines again.
