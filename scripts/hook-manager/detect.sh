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
if [ -x .git/hooks/pre-commit ] && [ ${#detected[@]} -eq 0 ]; then
  # Direct only if no manager already matched. Most hook managers also drop a
  # .git/hooks/pre-commit shim, but detection precedence runs manager checks first.
  if ! grep -q '# gitlore: managed' .git/hooks/pre-commit 2>/dev/null; then
    detected+=("direct")
  fi
fi

case "${#detected[@]}" in
  0) printf 'manual\n' ;;
  1) printf '%s\n' "${detected[0]}" ;;
  *) printf 'multi:%s\n' "$(IFS=,; echo "${detected[*]}")" ;;
esac
