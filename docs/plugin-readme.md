# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the full design. User-facing docs land in Plan 05.

## Development

Install bats-core first (`brew install bats-core` or `npm i -g bats`), then run tests: `bats tests/`

### Dependencies

- **python3 + PyYAML** (install via `pip install pyyaml` or `apt install python3-yaml`) — used by `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge YAML config files when `yq` is not available.
- **yq** (optional, `brew install yq` — must be the [mikefarah/yq](https://github.com/mikefarah/yq) Go build, *not* the kislyuk Python wrapper) — preferred over python3 for lefthook and overcommit wiring. Note: yq-based wiring strips pre-existing YAML comments from config files; the gitlore marker is preserved but user comments are not. Use the python3 path if you want comments retained.
