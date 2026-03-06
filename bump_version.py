#!/usr/bin/env python3
"""
MidnightQoL – TOC Version Bumper
==================================
Updates the '## Version:' line in every .toc file found under the repo root.

Usage:
    python3 bump_version.py <new_version>

Example:
    python3 bump_version.py 1.0.36

Called automatically by the tag-creation GitHub Action before tagging.
"""

import sys
import re
from pathlib import Path

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 bump_version.py <new_version>")

    new_version = sys.argv[1].lstrip("v")   # strip leading 'v' if present
    repo_root   = Path(__file__).parent

    toc_files = list(repo_root.rglob("*.toc"))
    if not toc_files:
        sys.exit("ERROR: No .toc files found under " + str(repo_root))

    for toc in toc_files:
        text = toc.read_text(encoding="utf-8")
        updated, count = re.subn(
            r"^(## Version:\s*).*$",
            rf"\g<1>{new_version}",
            text,
            flags=re.MULTILINE,
        )
        if count:
            toc.write_text(updated, encoding="utf-8")
            print(f"  Updated {toc.relative_to(repo_root)}  ->  {new_version}")
        else:
            print(f"  [WARN] No '## Version:' line found in {toc.relative_to(repo_root)}")

    print(f"\nDone -- {len(toc_files)} .toc file(s) processed.")

if __name__ == "__main__":
    main()
