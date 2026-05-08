#!/usr/bin/env python3
"""Generate a hybrid-search benchmark report from exported run JSONL files."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "evals"))

from metrics import evaluate, load_qrels, load_run, parse_ks  # noqa: E402


def parse_run_arg(raw: str) -> tuple[str | None, Path]:
    if "=" in raw:
        method, path = raw.split("=", 1)
        if not method:
            raise ValueError("--run method=path must include a method name")
        return method, Path(path)
    path = Path(raw)
    return None, path


def load_named_runs(run_args: list[str]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for raw in run_args:
        forced_method, path = parse_run_arg(raw)
        runs = load_run(path, default_method=forced_method or path.stem)
        for method, run in runs.items():
            merged[forced_method or method] = run
    return merged


def markdown_report(summary: dict[str, dict[str, float | int | None]], ks: list[int]) -> str:
    headers = ["Method", "Queries"]
    for k in ks:
        headers.extend([f"Recall@{k}", f"NDCG@{k}"])
    headers.extend(["P50 ms", "P95 ms", "P99 ms"])

    lines = [
        "# pg_retrieval_engine Hybrid Search Benchmark",
        "",
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] + ["---:"] * (len(headers) - 1)) + " |",
    ]

    for method, row in summary.items():
        values = [method, str(row["queries"])]
        for k in ks:
            values.extend([fmt(row[f"recall@{k}"]), fmt(row[f"ndcg@{k}"])])
        values.extend(
            [
                fmt(row["latency_p50_ms"]),
                fmt(row["latency_p95_ms"]),
                fmt(row["latency_p99_ms"]),
            ]
        )
        lines.append("| " + " | ".join(values) + " |")

    lines.extend(
        [
            "",
            "Required comparison set: dense, fts, rrf, rerank, and optional faiss.",
            "Use the same queries, qrels, K values, and latency measurement window for every run.",
        ]
    )
    return "\n".join(lines) + "\n"


def fmt(value: float | int | None) -> str:
    if value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    return f"{value:.6f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a dense/FTS/RRF/rerank/FAISS benchmark report.")
    parser.add_argument("--qrels", type=Path, required=True, help="TSV qrels: qid, doc_id, relevance")
    parser.add_argument(
        "--run",
        action="append",
        required=True,
        help="Run JSONL file, optionally named as method=path. Repeat for dense, fts, rrf, rerank, faiss.",
    )
    parser.add_argument("--ks", default="10", help="comma-separated K values, for example 10,20,100")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--output", type=Path, help="optional output file")
    args = parser.parse_args()

    ks = parse_ks(args.ks)
    summary = evaluate(load_qrels(args.qrels), load_named_runs(args.run), ks)

    if args.format == "json":
        rendered = json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    else:
        rendered = markdown_report(summary, ks)

    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
