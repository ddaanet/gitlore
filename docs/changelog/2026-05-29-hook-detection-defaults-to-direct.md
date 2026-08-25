# 2026-05-29 — Hook detection defaults to `direct`, not `manual`

`detect.sh` previously emitted `direct` only when an executable, untracked
`.git/hooks/pre-commit` already existed; a repo with no recognized manager and
no pre-existing hook (the common case) fell through to `manual`, which only
prints a snippet and modifies nothing — so the pre-push double-commit hook
silently never fired until hand-wired. Surfaced by dogfooding: gitlore's own
repo (gitmoji installed only `commit-msg`) sat on `manual`, so `just release`'s
`git push` never pushed the memory submodule. Detection now defaults the
no-manager case to `direct` (wire-direct installs
`.git/hooks/{pre-commit,pre-push}` stubs — always available, coexists with a
hand-rolled hook by appending). `manual` is no longer auto-detected; it stays a
hand-set sentinel and the multi-manager fallback. The release recipe
(`plugin-dev/release.just`) is intentionally left untouched — it is generic,
vendored tooling shared across plugins and must not know about gitlore's memory
submodule; the git pre-push hook is the correct layer. This repo wired via
`wire-direct.sh`. Detection tests updated; 153 green.
