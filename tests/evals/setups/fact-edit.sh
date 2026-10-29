#!/usr/bin/env bash
# Scenario fixture: a committed fact whose wording is about to go stale, so the
# agent's edit has a cause that lives only in the user's prompt.
#
# The diff shows the old number replaced by a new one. It cannot show why, and a
# summary that omits the why is the failure the scenario grades. The store is
# committed clean, so the edit is the only pending change when the agent starts.
#
# Runs with cwd = $EVAL_REPO, after setup_eval_repo.
set -euo pipefail

cat > memory/reference_api_rate_limit.md <<'BODY'
---
name: reference_api_rate_limit
description: "the partner API rate limit — requests per minute before 429s"
metadata:
  type: reference
---

The partner API allows 100 requests per minute per key. Past that it answers
429 with a Retry-After header, and the client backs off for that long.
BODY

printf -- '- [partner API rate limit](reference_api_rate_limit.md) — requests per minute before 429s\n' \
  >> memory/MEMORY.md

git -C memory add -A
git -C memory commit -q -m "Add partner API rate limit reference"
git -C memory branch -f live HEAD
