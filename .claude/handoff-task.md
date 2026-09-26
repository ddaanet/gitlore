## Current task

The four fixes for the macOS tail run are complete and gated on Linux. All four are about macOS and none has been exercised there, so a re-run of `scripts/test-macos.sh` on the Mac is what checks them; expect the header to name the borrowed `python3` and the run to reach the hygiene and `wire-*` cases with PyYAML available. Nothing else is mid-flight.
