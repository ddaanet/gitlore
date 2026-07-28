## Remaining

- Cross-cutting memory cleanup: normalize `name:` frontmatter to the filename stem across the whole store (`ddaanet/feedback_no_in_place_other_repos.md` carries `name: feedback-no-in-place-other-repos` — hyphens against an underscored stem), and re-audit dangling `[[...]]` links store-wide.
- Compact the `MEMORY.md` index, at ~22.8KB against the 24.4KB read-truncation limit. Needs an adversarial audit of the diff per `feedback_index_compaction_triggers` — don't trim solo, and don't rush it under time pressure either.
- Explain the live pointer loss for gitlore's own memory store.
- Migrate `micro` (~40 facts) — settle a real memory remote first; it and `general` still point at a local `./.git/gitlore-placeholder`. Then `gitmoji` -> `general` -> `home` -> `devddaanet` -> `skills` -> `candidature` -> `edify` -> `Emploi` -> `cwd-safety`.