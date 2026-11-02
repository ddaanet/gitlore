## Remaining

- Commit 3 of plans/2026-11-01-silent-tier-line-loss.md: await green (report /tmp/claude/compose-s3-green.md), then medium review, triage, fix, review the fix.
- Execute plans/2026-11-02-no-pin-loop.md (approved), probes first. It removes the pin loop's submodule update and detach, the memory detach at session-start.sh:193, the pin check's put-back, the killed-take diagnostic branch and its TODO line, and the on-pin guard around gitlore_compose_pending. It adds gitlore-compose --up <tier> and an abort mode on /gitlore:resolve. Commit the plan file with its first commit.
- /gitlore:index-audit.
- xhigh release review of dev against main.
