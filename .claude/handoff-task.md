## Current task

Cutting the release that carries the tier `live`-ahead adoption to installed
repos, in the order the user named: update the vendored `plugin-dev` subtree,
run the preflight, publish memory with `/gitlore:push`, then `just release`.
The subtree update pins a `dist-vX.Y.Z` tag — never `main`, and never the bare
source tag, whose root tree is the toolkit's own working environment.
