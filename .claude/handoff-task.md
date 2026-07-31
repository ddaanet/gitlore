## Current task

Nothing is mid-flight. The `docs/` + `plans/` layout from
`brief-docs-plans-layout.md` is adopted in full: plans and specs live in a root
`plans/`, and `docs/changelog.md` is an index over 61 frozen per-entry bodies.

## Open decisions

- Whether an applied brief belongs in `plans/` or stays in the root inbox.
  `brief-docs-plans-layout.md` is now applied and still sits at the repo root,
  while `brief-compose-full-tier-clear-gap.md` and
  `brief-memory-commit-batch-model-channel.md` moved into `plans/` with the
  other prospective content.
- Whether to bump the plugin version and release now, or batch the release with
  the remaining memory work. The D21 detector reaches no other repo until a
  release lands and each repo runs `/plugin update`, so every session started
  elsewhere in the meantime keeps the failure it exists to explain.
- `scripts/lib/util.sh`'s stale-hooksDir wrapper hint is pinned by no test — the
  wording changed to name `claude -c` and the suite stayed green. Whether the
  emitted wrapper text is worth pinning, or is deliberately left loose.