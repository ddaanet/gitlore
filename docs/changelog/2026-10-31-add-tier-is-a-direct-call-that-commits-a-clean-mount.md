# 2026-10-31 — add-tier is a direct call that commits a clean mount

D71 retires the intent-file route D32 gave `/gitlore:add-tier`. The probe and
the argument are in the D71 section of
[tiered-memory.md](../references/tiered-memory.md).

**What the user sees.** `/gitlore:add-tier` runs `gitlore-add-tier` directly,
sandboxed, with the url's host (and `api.github.com` for a mount's visibility
check) in `allowed_domains`; the intent goes on stdin through a quoted heredoc,
as `gitlore-commit` takes its summary. A mount into a clean memory store commits
itself under a canned message, `mount <tier> tier from <url>` (create:
`create <tier> tier at <url>`), and stages the moved memory gitlink in the
parent. A store with unapproved work pending is left with the mount staged for
the next `gitlore:commit`, and the report says so. Triage moves stay on the
`gitlore:commit` approval path.

**What went.** The `.claude/gitlore-add-tier` intent file, the `PostToolBatch`
hook `add-tier-batch.sh` and its `hooks.json` entry, and the `.gitignore` line.
D32's routing is superseded; its mount/create convergence and activate-as-last-
step stand. Eval scenario `03-add-tier` is a single turn grading the canned
commit.
