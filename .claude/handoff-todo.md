## Remaining

- Normalize `name:` frontmatter to the filename stem across the whole memory store (`ddaanet/feedback_no_in_place_other_repos.md` carries `name: feedback-no-in-place-other-repos`, hyphens against an underscored stem), and re-audit dangling `[[...]]` links store-wide.
- Compact the `MEMORY.md` index, at ~23KB against the 24.4KB read-truncation limit. Needs an adversarial audit of the diff per `feedback_index_compaction_triggers` — don't trim solo, and don't rush it under time pressure.
- Explain the live pointer loss for gitlore's own memory store.
- Migrate `micro` (~40 facts) once a real memory remote is settled; it and `general` still point at a local `./.git/gitlore-placeholder`. Then `gitmoji` -> `general` -> `home` -> `devddaanet` -> `skills` -> `candidature` -> `edify` -> `Emploi` -> `cwd-safety`.