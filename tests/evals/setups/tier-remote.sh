#!/usr/bin/env bash
# Scenario fixture: a tier remote that exists but is not mounted here.
#
# Runs with cwd = $EVAL_REPO, after setup_eval_repo. Leaves a bare repo at
# .tier-remote.git shaped the way a tier remote must be — default branch `main`
# with `live` alongside, because a `live` default gets checked out AS A BRANCH by
# the mount and the ff-only `fetch origin live:live` then refuses forever.
#
# The seeded index carries one pointer line, so activation has something for
# composition to splice up into the root index. Its target file is seeded too:
# not required by the compose validation, but a store whose pointers dangle is
# not the happy path we are grading.
set -euo pipefail

BARE="$PWD/.tier-remote.git"
seed=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-eval-tier.XXXXXX")

git init -q -b main "$seed"
git -C "$seed" config user.email "eval@test.com"
git -C "$seed" config user.name "Eval Test"

cat > "$seed/MEMORY.md" <<'EOF'
---
description: "Cross-project facts shared by every acme repository"
---

# acme tier index

- [staging DB is shared](reference_acme_staging_db.md) — every acme service points at ONE staging database; a destructive migration there breaks other teams
EOF

cat > "$seed/reference_acme_staging_db.md" <<'EOF'
---
name: reference_acme_staging_db
description: "every acme service points at ONE staging database; a destructive migration there breaks other teams"
metadata:
  type: reference
---

There is a single shared staging database across all acme services. Treat any
destructive migration against it as a cross-team change.
EOF

git -C "$seed" add -A
git -C "$seed" commit -q -m "Seed acme tier index"
git -C "$seed" branch live

git clone -q --bare "$seed" "$BARE"
rm -rf "$seed"
