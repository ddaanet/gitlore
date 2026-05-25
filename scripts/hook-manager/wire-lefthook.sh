#!/usr/bin/env bash
# wire-lefthook.sh — inject gitlore wrappers into lefthook.yml
#
# YAML duplicate-key safety: lefthook uses gopkg.in/yaml.v3 which silently takes
# the last value for duplicate keys (same as PyYAML safe_load). A naive append of
# a second `pre-commit:` block would silently discard the user's existing commands.
# We therefore use `yq` (preferred) or `python3` to do a proper in-place merge.
set -euo pipefail

CONFIG="lefthook.yml"
[ -f "$CONFIG" ] || CONFIG=".lefthook.yml"
[ -f "$CONFIG" ] || { echo "wire-lefthook: no lefthook config found" >&2; exit 1; }

# Idempotency check — if marker already present, nothing to do.
if grep -q '# gitlore: managed' "$CONFIG"; then
  # Still write the sentinel (handles case where .claude/ was deleted but YAML was not).
  mkdir -p .claude
  printf 'lefthook install\n' > .claude/gitlore-hook-setup
  exit 0
fi

# Merge gitlore commands into the config using yq (preferred) or python3.
# yq detection: must distinguish mikefarah/yq (Go, expected flags) from
# kislyuk/yq (Python jq wrapper, incompatible flags). mikefarah's `yq --version`
# output contains either "mikefarah" or "version v<N>"; kislyuk's prints
# "yq <N>.<N>.<N>" with no leading "v" and no mikefarah URL.
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -qE 'mikefarah|version v[0-9]'; then
  # yq (mikefarah/yq v4) — deep-merges commands without clobbering existing entries.
  yq -i '.pre-commit.commands.gitlore.run = "$(git rev-parse --git-common-dir)/gitlore-pre-commit"' "$CONFIG"
  yq -i '.pre-push.commands.gitlore.run   = "$(git rev-parse --git-common-dir)/gitlore-pre-push"'   "$CONFIG"
  # Append the marker comment.  yq strips comments, so we append it as a plain line.
  # Note: any pre-existing YAML comments in lefthook.yml will have been stripped
  # by the yq round-trip.  See docs/plugin-readme.md.
  printf '\n# gitlore: managed\n' >> "$CONFIG"
elif python3 -c 'import yaml' 2>/dev/null; then
  python3 - "$CONFIG" <<'PYEOF'
import sys, yaml

path = sys.argv[1]
with open(path) as fh:
    data = yaml.safe_load(fh) or {}

for hook, wrapper in (
    ('pre-commit', '$(git rev-parse --git-common-dir)/gitlore-pre-commit'),
    ('pre-push',   '$(git rev-parse --git-common-dir)/gitlore-pre-push'),
):
    data.setdefault(hook, {}).setdefault('commands', {})['gitlore'] = {'run': wrapper}

with open(path, 'w') as fh:
    yaml.dump(data, fh, default_flow_style=False, allow_unicode=True)
    fh.write('\n# gitlore: managed\n')
PYEOF
else
  echo "wire-lefthook: need mikefarah/yq or python3 with PyYAML to safely merge lefthook.yml" >&2
  exit 1
fi

mkdir -p .claude
printf 'lefthook install\n' > .claude/gitlore-hook-setup
