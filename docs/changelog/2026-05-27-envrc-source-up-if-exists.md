# 2026-05-27 — `source_up_if_exists` added to fresh `.envrc`

When `emit-launcher.sh` creates `.envrc` from scratch, it now writes `source_up_if_exists` as the first line so parent-directory direnv configs are inherited. Existing `.envrc` files are not modified.
