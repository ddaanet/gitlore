#!/usr/bin/env bash
# wire-overcommit.sh — inject gitlore wrappers into .overcommit.yml
#
# YAML duplicate-key safety: overcommit uses Ruby's Psych.safe_load which silently
# takes the last value for duplicate keys. A naive append of a second `PreCommit:`
# block would silently discard the user's existing PreCommit configuration.
# We therefore use `yq` (preferred) or `python3` to do a proper in-place merge.
set -euo pipefail

CONFIG=".overcommit.yml"
[ -f "$CONFIG" ] || { echo "wire-overcommit: no $CONFIG" >&2; exit 1; }

# Idempotency check — if marker already present, nothing to do.
if grep -q '# gitlore: managed' "$CONFIG"; then
  mkdir -p .claude
  printf 'overcommit --install\n' > .claude/gitlore-hook-setup
  exit 0
fi

# Merge gitlore entries into the config using yq (preferred) or python3.
# yq detection: must distinguish mikefarah/yq (Go, expected flags) from
# kislyuk/yq (Python jq wrapper, incompatible flags). mikefarah's `yq --version`
# output contains either "mikefarah" or "version v<N>"; kislyuk's prints
# "yq <N>.<N>.<N>" with no leading "v" and no mikefarah URL.
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -qE 'mikefarah|version v[0-9]'; then
  # yq (mikefarah/yq v4) — deep-merges entries without clobbering existing ones.
  yq -i '.PreCommit.gitlore.enabled = true | .PreCommit.gitlore.command = [".git/gitlore-pre-commit"]' "$CONFIG"
  yq -i '.PrePush.gitlore.enabled = true | .PrePush.gitlore.command = [".git/gitlore-pre-push"]'       "$CONFIG"
  # Append the marker comment. yq strips comments, so we append it as a plain line.
  # Note: any pre-existing YAML comments in .overcommit.yml will have been stripped
  # by the yq round-trip. See docs/plugin-readme.md.
  printf '\n# gitlore: managed\n' >> "$CONFIG"
elif python3 -c 'import yaml' 2>/dev/null; then
  python3 - "$CONFIG" <<'PYEOF'
import sys, yaml

path = sys.argv[1]
with open(path) as fh:
    data = yaml.safe_load(fh) or {}

for hook, key, wrapper in (
    ('PreCommit', 'gitlore-pre-commit', '.git/gitlore-pre-commit'),
    ('PrePush',   'gitlore-pre-push',   '.git/gitlore-pre-push'),
):
    hook_data = data.setdefault(hook, {})
    # key name used in yaml is just 'gitlore' for both
    hook_data['gitlore'] = {
        'enabled': True,
        'command': [wrapper],
    }

with open(path, 'w') as fh:
    yaml.dump(data, fh, default_flow_style=False, allow_unicode=True)
    fh.write('\n# gitlore: managed\n')
PYEOF
else
  echo "wire-overcommit: need mikefarah/yq or python3 with PyYAML to safely merge .overcommit.yml" >&2
  exit 1
fi

mkdir -p .claude
printf 'overcommit --install\n' > .claude/gitlore-hook-setup
