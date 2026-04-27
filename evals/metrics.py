#!/usr/bin/env python3
"""Offline metrics for hybrid retrieval evaluation.

Input conventions:
- qrels TSV: qid, doc_id, relevance
- run JSONL, query-level:
  {"qid":"q1","method":"rrf","latency_ms":12.3,
   "results":[{"id":"d1","rank":1,"score":0.1},{"id":"d2"}]}
- run JSONL, row-level:
  {"qid":"q1","method":"rrf","doc_id":"d1","rank":1,"latency_ms":12.3}
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


@dataclass
class RunQuery:
    qid: str
    doc_ids: list[str] = field(default_factory=list)
    latency_ms: float | None = None


Qrels = dict[str, dict[str, float]]
Runs = dict[str, dict[str, RunQuery]]


def load_qrels(path: Path) -> Qrels:
    qrels: Qrels = {}
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        for line_no, row in enumerate(reader, 1):
            if not row or row[0].startswith("#"):
                continue
            if len(row) < 3:
                raise ValueError(f"{path}:{line_no}: expected qid, doc_id, relevance")
            qid, doc_id, relevance = row[:3]
            qrels.setdefault(str(qid), {})[str(doc_id)] = float(relevance)
    return qrels


def _doc_id_from_hit(hit: Any) -> str:
    if isinstance(hit, dict):
        for key in ("doc_id", "id"):
            if key in hit:
                return str(hit[key])
        raise ValueError(f"result hit has no doc_id/id field: {hit!r}")
    return str(hit)


def _sort_row_hits(hits: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def key(hit: dict[str, Any]) -> tuple[float, float, str]:
        rank = hit.get("rank")
        score = hit.get("score")
        if rank is not None:
            return (float(rank), 0.0, _doc_id_from_hit(hit))
        if score is not None:
            return (math.inf, -float(score), _doc_id_from_hit(hit))
        return (math.inf, 0.0, _doc_id_from_hit(hit))

    return sorted(hits, key=key)


def load_run(path: Path, default_method: str = "run") -> Runs:
    grouped_rows: dict[tuple[str, str], list[dict[str, Any]]] = {}
    runs: Runs = {}

    with path.open(encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            qid = str(record["qid"])
            method = str(record.get("method", default_method))

            if "results" in record:
                query = RunQuery(
                    qid=qid,
                    doc_ids=[_doc_id_from_hit(hit) for hit in record["results"]],
                    latency_ms=(
                        float(record["latency_ms"]) if record.get("latency_ms") is not None else None
                    ),
                )
                runs.setdefault(method, {})[qid] = query
                continue

            if "doc_id" not in record and "id" not in record:
                raise ValueError(f"{path}:{line_no}: expected results array or doc_id/id")
            grouped_rows.setdefault((method, qid), []).append(record)

    for (method, qid), hits in grouped_rows.items():
        latency_values = [
            float(hit["latency_ms"]) for hit in hits if hit.get("latency_ms") is not None
        ]
        runs.setdefault(method, {})[qid] = RunQuery(
            qid=qid,
            doc_ids=[_doc_id_from_hit(hit) for hit in _sort_row_hits(hits)],
            latency_ms=max(latency_values) if latency_values else None,
        )

    return runs


def _dedupe(doc_ids: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for doc_id in doc_ids:
        if doc_id in seen:
            continue
        seen.add(doc_id)
        unique.append(doc_id)
    return unique


def recall_at_k(qrels: Qrels, run: dict[str, RunQuery], k: int) -> float:
    values: list[float] = []
    for qid, labels in qrels.items():
        relevant = {doc_id for doc_id, rel in labels.items() if rel > 0}
        if not relevant:
            continue
        retrieved = set(_dedupe(run.get(qid, RunQuery(qid)).doc_ids)[:k])
        values.append(len(relevant & retrieved) / len(relevant))
    return sum(values) / len(values) if values else 0.0


def ndcg_at_k(qrels: Qrels, run: dict[str, RunQuery], k: int) -> float:
    values: list[float] = []
    for qid, labels in qrels.items():
        gains = labels
        ideal_rels = sorted((rel for rel in gains.values() if rel > 0), reverse=True)[:k]
        idcg = _dcg(ideal_rels)
        if idcg <= 0:
            continue
        retrieved_rels = [gains.get(doc_id, 0.0) for doc_id in _dedupe(run.get(qid, RunQuery(qid)).doc_ids)[:k]]
        values.append(_dcg(retrieved_rels) / idcg)
    return sum(values) / len(values) if values else 0.0


def _dcg(relevances: Iterable[float]) -> float:
    return sum((2.0**rel - 1.0) / math.log2(rank + 1.0) for rank, rel in enumerate(relevances, 1))


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    if p < 0 or p > 100:
        raise ValueError("percentile must be in range 0..100")
    ordered = sorted(values)
    index = max(0, math.ceil((p / 100.0) * len(ordered)) - 1)
    return ordered[index]


def evaluate(qrels: Qrels, runs: Runs, ks: list[int]) -> dict[str, dict[str, float | int | None]]:
    summary: dict[str, dict[str, float | int | None]] = {}
    for method, run in sorted(runs.items()):
        latencies = [query.latency_ms for query in run.values() if query.latency_ms is not None]
        row: dict[str, float | int | None] = {
            "queries": len(run),
            "latency_p50_ms": percentile(latencies, 50),
            "latency_p95_ms": percentile(latencies, 95),
            "latency_p99_ms": percentile(latencies, 99),
        }
        for k in ks:
            row[f"recall@{k}"] = recall_at_k(qrels, run, k)
            row[f"ndcg@{k}"] = ndcg_at_k(qrels, run, k)
        summary[method] = row
    return summary


def print_table(summary: dict[str, dict[str, float | int | None]], ks: list[int]) -> None:
    headers = ["method", "queries"]
    for k in ks:
        headers.extend([f"recall@{k}", f"ndcg@{k}"])
    headers.extend(["latency_p50_ms", "latency_p95_ms", "latency_p99_ms"])

    print("\t".join(headers))
    for method, row in summary.items():
        values = [method, str(row["queries"])]
        for k in ks:
            values.extend([_format(row[f"recall@{k}"]), _format(row[f"ndcg@{k}"])])
        values.extend(
            [
                _format(row["latency_p50_ms"]),
                _format(row["latency_p95_ms"]),
                _format(row["latency_p99_ms"]),
            ]
        )
        print("\t".join(values))


def _format(value: float | int | None) -> str:
    if value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    return f"{value:.6f}"


def parse_ks(raw: str) -> list[int]:
    ks = [int(part) for part in raw.split(",") if part.strip()]
    if not ks or any(k < 1 for k in ks):
        raise ValueError("ks must contain positive integers")
    return ks


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate retrieval runs with Recall@K, NDCG@K, and tail latency.")
    parser.add_argument("--qrels", type=Path, required=True, help="TSV qrels: qid, doc_id, relevance")
    parser.add_argument("--run", type=Path, required=True, help="JSONL retrieval run")
    parser.add_argument("--ks", default="10", help="comma-separated K values, for example 10,20,100")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of TSV")
    args = parser.parse_args()

    ks = parse_ks(args.ks)
    summary = evaluate(load_qrels(args.qrels), load_run(args.run), ks)
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print_table(summary, ks)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
