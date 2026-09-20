## Current task

A sweep of the todo list: the gates suite shares one discovery run, `approve()` and `mount_tier_at_live()` live once in `tests/helpers/tier-fixtures.bash`, and `resolve.sh` publishes memory's `live` to a never-published remote only through `check_store_gates`, after every tier gate. The stranded-tier-`live` question was probed and self-heals through `gitlore_repair_stranded_live`. A macOS check script, `plans/macos-check/run.sh`, waits for my human partner to run it on a Mac and hand back `plans/macos-check/out/report.txt`; nothing else is in flight.
