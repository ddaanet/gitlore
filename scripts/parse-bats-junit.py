#!/usr/bin/env python3
"""Per-suite verdicts from a bats junit report, for `run-bats-cached.sh`.

Reads the report path as its one argument and writes one line per
`<testsuite>`, in report order: its failure-or-error count, a tab, its `name`.
bats names a testsuite after the input path with the inputs' shared leading
directory stripped — neither the basename nor the path the caller knows the
suite by, but always a suffix of that path, which is what the caller checks.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET


def main() -> int:
    report_path = sys.argv[1]
    root = ET.parse(report_path).getroot()
    for suite in root.findall("testsuite"):
        failed = int(suite.get("failures", "0")) + int(suite.get("errors", "0"))
        print(f"{failed}\t{suite.get('name', '')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
