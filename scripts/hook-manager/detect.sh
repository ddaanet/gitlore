#!/usr/bin/env bash
set -euo pipefail

detected=()

if [ -f lefthook.yml ] || [ -f .lefthook.yml ]; then
  detected+=("lefthook")
fi
if [ -d .husky ]; then
  detected+=("husky")
fi
if [ -f .overcommit.yml ] || [ -f .git/hooks/overcommit-hook ]; then
  detected+=("overcommit")
fi
case "${#detected[@]}" in
  # No recognized hook manager → direct wiring into the shared .git/hooks dir,
  # which is available in every git repo. wire-direct appends the pre-push stub
  # to a hand-rolled pre-push (coexisting) or creates a fresh one. `manual` is no
  # longer auto-detected — it remains a valid sentinel a user can set by hand,
  # and is still emitted for the ambiguous multi-manager case below.
  0) printf 'direct\n' ;;
  1) printf '%s\n' "${detected[0]}" ;;
  *) printf 'multi:%s\n' "$(IFS=,; echo "${detected[*]}")" ;;
esac
