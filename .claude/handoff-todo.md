## Remaining

- Bump the plugin version before releasing the `/gitlore:push` feature; `check-version` is in sync at 0.4.3.
- Normalize `name:` frontmatter to the filename stem across the whole memory store (`ddaanet/feedback_no_in_place_other_repos.md` carries hyphens against an underscored stem), and re-audit dangling `[[...]]` links store-wide.
- Explain the live pointer loss for gitlore's own memory store.
- Place or apply the four `brief-*.md` files sitting at the repo root, in their target repos.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled; it and `general` still point at a local `./.git/gitlore-placeholder`. Then `gitmoji` -> `general` -> `home` -> `devddaanet` -> `skills` -> `candidature` -> `edify` -> `Emploi` -> `cwd-safety`.