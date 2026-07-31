## Current task

Nothing is mid-flight. `docs/plans/2026-07-31-14-stale-plugin-root-notice.md` is
executed in full — the `PostToolBatch` upgrade detector, its bats cover, D21 and
the D5 extension, the memory update, and the brief handed to `handoff` — and
`just precommit` is green.

## Open decisions

- Whether to carry out the `docs/plans/` → root `plans/` migration. It was
  deferred only until the D21 plan stopped being in flight, which it now is.
  `handoff` already keeps plans at its repo root.
- Whether to bump the plugin version and release now, or batch the release with
  the remaining memory work. The D21 detector reaches no other repo until a
  release lands and each repo runs `/plugin update`, so every session started
  elsewhere in the meantime keeps the failure it exists to explain.
- `scripts/lib/util.sh`'s stale-hooksDir wrapper hint is pinned by no test — the
  wording changed to name `claude -c` and the suite stayed green. Whether the
  emitted wrapper text is worth pinning, or is deliberately left loose.