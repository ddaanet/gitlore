#!/usr/bin/env bash
# Scenario fixture: a memory body whose payload is NOT in its index line.
#
# The index line carries the trigger keywords and nothing else — that is what an
# index line is for. The canary lives only in the body, so an answer containing
# it proves the body reached context, and an answer without it proves the index
# alone was never enough. The scenario's `initial_memory` supplies the matching
# root index line.
#
# Runs with cwd = $EVAL_REPO, after setup_eval_repo.
set -euo pipefail

cat > memory/reference_deploy_lock.md <<'EOF'
---
name: reference_deploy_lock
description: "a stuck deploy.lock after a failed rollout — clearing it needs the unlock token, not a plain rm"
metadata:
  type: reference
---

A rollout that dies mid-flight leaves `deploy.lock` behind holding a dead pid.
Deleting the file by hand corrupts the rollout ledger and the next deploy
silently skips the migration step.

Clear it with the unlock tool instead, which reconciles the ledger first:

```
svc-unlock --force --token ORBITAL-PANGOLIN-4471
```

The token is fixed per environment and lives here so nobody has to page the
on-call to get it.
EOF

# Committed, so the store is clean when the agent starts: a dirty memory store
# would drag the commit gate into a scenario that is grading recall.
GITLORE_MEMORY_COMMIT=1 git -C memory add -A
GITLORE_MEMORY_COMMIT=1 git -C memory commit -q -m "Add deploy lock reference"
git -C memory branch -f live HEAD
