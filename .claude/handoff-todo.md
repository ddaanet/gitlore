## Remaining

- Cross-cutting memory cleanup: normalize `name:` frontmatter to the
  filename stem across the whole store (confirmed drift example:
  `memory/reference_nested_submodule_tier.md`'s `name:` was
  `nested-submodule-tier-mechanics` before that file was deleted — the
  pattern likely recurs elsewhere), and re-audit dangling `[[...]]` links
  store-wide.
- Compact the `MEMORY.md` index. Was ~23.3KB / 91%+ of the 24.4KB
  read-truncation limit (25600-byte budget) as of the last check, and this
  session added another memory augmentation. Needs an adversarial audit of
  the diff per `feedback_index_compaction_triggers` — don't trim solo, and
  don't rush it under time pressure either.
- Explain the live pointer loss for gitlore's own memory store — the
  0.4.2 plugin tag itself is done, but the pointer-loss investigation
  behind that todo item is not.
- Migrate `micro` (~40 facts) — settle a real memory remote first; it and
  `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature`
  → `edify` → `Emploi` → `cwd-safety`.
