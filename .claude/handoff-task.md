## Current task

Fixed the `/plugin install` failure by pushing the stranded memory gitlink commit (`12aa664`, memory `main` was 5 ahead of `origin/main`) to the gitlore-memory remote — confirm the install now completes end-to-end.

## Open decisions

- How to harden the release flow so a release can never tag/push the parent while the memory gitlink SHA is unreachable on the gitlore-memory remote. Per the "preflight stays generic" rule, this project-specific gate likely belongs in the project's own release tooling (Makefile/CI), not ddaa:preflight. The `0.2.1` tag was cut with these 5 memory commits still local, which is what broke install.
