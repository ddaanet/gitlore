#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
GITLORE_HOME="${GITLORE_HOME:-$HOME/.gitlore}"
bindir="$GITLORE_HOME/bin"

mkdir -p "$bindir"
cp "$PLUGIN_ROOT/scripts/install/launcher-shim" "$bindir/claude"
chmod 755 "$bindir/claude"

case "$(basename "${SHELL:-sh}")" in
  fish) line="set -gx PATH $bindir \$PATH" ;;
  *)    line="export PATH=\"$bindir:\$PATH\"" ;;
esac

cat >&2 <<EOF
gitlore launcher installed at $bindir/claude.
Add this line to your shell rc to activate it (gitlore will not edit your rc):

    $line

Then restart your shell. The shim auto-activates only in gitlore-enabled repos and no-ops everywhere else.
EOF
