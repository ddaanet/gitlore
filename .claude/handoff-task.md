## Current task

The review of the commit that split `docs/design.md` into a hub plus reference nodes: its first pass (essential information the split dropped) is closed with fixes landed; what resumes is the review's later passes, which have not been scoped. The docs hard-wrap gate (`just format-docs`, rumdl pinned through `uv.lock`, first step of `precommit`) is complete and green, with the six malformed nested fences in plans fixed and `check-docs-links.py` made robust to wrapped summary bullets.
