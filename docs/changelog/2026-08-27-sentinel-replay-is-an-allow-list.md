# 2026-08-27 — The hook-manager sentinel is replayed from an allow-list, not handed to a shell (NFR7, D45)

Found by a shell-gotchas audit of everything changed since 0.5.0, filed as a
trust-model finding rather than a shell defect. `SessionStart` replays
`.claude/gitlore-hook-setup` so a clone gets its hook-manager wiring back
without re-running install. The replay's fallback arm was `sh -c "$cmd"` on
the file's first line. The file is tracked, so the first session start in any
freshly cloned repo executed whatever line the clone carried, gated only by
`gitlore.enabled` in the equally tracked `.claude/settings.json`.

The wire scripts are the only writers, and they write exactly five lines:
`direct`, `manual`, `lefthook install`, `npx husky`, `overcommit --install`.
The replay now matches against those literals. An unrecognized line runs
nothing and is reported on `systemMessage`, naming the three commands gitlore
replays and pointing at `manual` for anything else. The original design's
reason for the open arm — wiring an unsupported manager by hand-editing the
sentinel — is served by `manual` plus the copy-paste snippet, without gitlore
running a stranger's line. Recorded as D45 in
[installation.md](../references/installation.md).
