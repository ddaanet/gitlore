# 2026-05-26 — Commands made script-driven (D7 / 12-factor-agents)

`install.md` collapsed to 2 steps — gather inputs, run `run.sh` once.
Direnv/global-shim dispatch moved into `run.sh` (if direnv found:
`direnv allow`; else: `global-shim.sh`). `/gitlore:install-launcher` command
removed; its behavior is now automatic. `resolve.md` converted to a
self-triggering skill: description updated with `gitlore: memory merge prepared`
trigger pattern; commit-triggered entry mode added (skips initial script run —
directive already in context from the hook); `Resume commit` step added to retry
the original commit after resolve succeeds.
