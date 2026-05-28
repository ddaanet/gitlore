## Current task

Harden gitlore's release flow so it can never tag/push the parent repo while the memory submodule's gitlink SHA is still unreachable on the gitlore-memory remote — the failure mode that broke `/plugin install` at 0.2.1; the band-aid (pushing the stranded memory commit) is done, the systemic gate is not.

## Open decisions

- Where the gate lives and its exact mechanism: per the preflight-stays-generic rule this project-specific check belongs in gitlore's own release tooling (justfile/Makefile/CI), not ddaa:preflight. Likely a `just release` preflight step that confirms the committed `memory` gitlink is reachable on `origin/main` of gitlore-memory (e.g. `git -C memory branch -r --contains <gitlink>`) before allowing the parent tag + push.
