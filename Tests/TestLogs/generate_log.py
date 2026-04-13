#!/usr/bin/env python3
"""Generate a log file with a specified number of rows by repeating content from a source log file.

Usage:
    python3 generate_log.py <source_log> <row_count> [output_file]

Examples:
    python3 generate_log.py small.log 1000000 1M.log
    python3 generate_log.py medium.log 5000000             # outputs to stdout
    python3 generate_log.py small.log 100000 ~/Downloads/100k.log
"""

import sys
import os
import itertools


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(1)

    source_path = sys.argv[1]
    target_rows = int(sys.argv[2])
    output_path = sys.argv[3] if len(sys.argv) > 3 else None

    # Resolve source relative to script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if not os.path.isabs(source_path):
        source_path = os.path.join(script_dir, source_path)

    if not os.path.exists(source_path):
        print(f"Error: source file not found: {source_path}", file=sys.stderr)
        sys.exit(1)

    # Read source lines (strip trailing newlines, skip blank lines)
    with open(source_path, "r") as f:
        source_lines = [line.rstrip("\n") for line in f if line.strip()]

    if not source_lines:
        print("Error: source file is empty", file=sys.stderr)
        sys.exit(1)

    # Generate output
    out = open(output_path, "w") if output_path else sys.stdout
    try:
        written = 0
        for line in itertools.cycle(source_lines):
            if written >= target_rows:
                break
            out.write(line + "\n")
            written += 1

            # Progress to stderr every 500k lines
            if output_path and written % 500_000 == 0:
                print(f"  {written:,} / {target_rows:,} rows...", file=sys.stderr)

        if output_path:
            size_mb = os.path.getsize(output_path) / (1024 * 1024)
            print(f"Done: {written:,} rows, {size_mb:.1f} MB → {output_path}", file=sys.stderr)
    finally:
        if output_path:
            out.close()


if __name__ == "__main__":
    main()
