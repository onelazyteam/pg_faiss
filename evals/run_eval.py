#!/usr/bin/env python3
"""Evaluate exported retrieval runs.

This runner intentionally stays offline. SQL or benchmark scripts should export
one JSONL file per experiment, then this script computes comparable quality and
latency metrics.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from metrics import evaluate, load_qrels, load_run, parse_ks, print_table


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate hybrid retrieval result JSONL files.")
    parser.add_argument("--qrels", type=Path, required=True)
    parser.add_argument("--run", type=Path, action="append", required=True, help="JSONL run file; may be repeated")
    parser.add_argument("--ks", default="10", help="comma-separated K values")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    qrels = load_qrels(args.qrels)
    ks = parse_ks(args.ks)
    merged_runs = {}
    for run_path in args.run:
        for method, run in load_run(run_path, default_method=run_path.stem).items():
            merged_runs[method] = run

    summary = evaluate(qrels, merged_runs, ks)
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_table(summary, ks)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
