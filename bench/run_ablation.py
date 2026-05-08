#!/usr/bin/env python3
"""Convenience wrapper for the standard hybrid-search ablation report."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the dense/FTS/RRF/rerank/FAISS ablation report.")
    parser.add_argument("--qrels", type=Path, required=True)
    parser.add_argument("--dense", type=Path, required=True)
    parser.add_argument("--fts", type=Path, required=True)
    parser.add_argument("--rrf", type=Path, required=True)
    parser.add_argument("--rerank", type=Path)
    parser.add_argument("--faiss", type=Path)
    parser.add_argument("--ks", default="10,20")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    bench = Path(__file__).with_name("run_bench.py")
    cmd = [
        sys.executable,
        str(bench),
        "--qrels",
        str(args.qrels),
        "--run",
        f"dense={args.dense}",
        "--run",
        f"fts={args.fts}",
        "--run",
        f"rrf={args.rrf}",
        "--ks",
        args.ks,
        "--format",
        args.format,
    ]
    if args.rerank:
        cmd.extend(["--run", f"rerank={args.rerank}"])
    if args.faiss:
        cmd.extend(["--run", f"faiss={args.faiss}"])
    if args.output:
        cmd.extend(["--output", str(args.output)])

    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
