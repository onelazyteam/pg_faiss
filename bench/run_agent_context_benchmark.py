#!/usr/bin/env python3
"""Agent context retrieval benchmark.

The runner evaluates exported Agent/RAG retrieval results. It keeps the same
offline contract as run_bench.py, but adds enterprise-agent metrics:

- Context Recall@K
- Citation Hit Rate@K
- Tool-use Context Hit Rate@K
- Permission Violation Rate@K
- P50/P95/P99 latency
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "evals"))

from metrics import load_qrels, parse_ks, percentile  # noqa: E402


@dataclass
class AgentQuery:
    qid: str
    allowed_doc_ids: set[str] | None = None
    required_tool_context_ids: set[str] = field(default_factory=set)


@dataclass
class AgentRunQuery:
    qid: str
    doc_ids: list[str] = field(default_factory=list)
    citation_ids: list[str] = field(default_factory=list)
    tool_context_ids: list[str] = field(default_factory=list)
    explicit_permission_violations: int = 0
    latency_ms: float | None = None


AgentRuns = dict[str, dict[str, AgentRunQuery]]


def load_agent_queries(path: Path | None) -> dict[str, AgentQuery]:
    if path is None:
        return {}

    queries: dict[str, AgentQuery] = {}
    with path.open(encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            qid = str(record["qid"])
            allowed_raw = record.get("allowed_doc_ids")
            queries[qid] = AgentQuery(
                qid=qid,
                allowed_doc_ids=({str(doc_id) for doc_id in allowed_raw} if allowed_raw is not None else None),
                required_tool_context_ids={str(doc_id) for doc_id in record.get("required_tool_context_ids", [])},
            )
    return queries


def load_agent_run(path: Path, default_method: str) -> AgentRuns:
    grouped_rows: dict[tuple[str, str], list[dict[str, Any]]] = {}
    runs: AgentRuns = {}

    with path.open(encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            qid = str(record["qid"])
            method = str(record.get("method", default_method))

            if "results" in record:
                runs.setdefault(method, {})[qid] = _query_from_hits(
                    qid,
                    record["results"],
                    latency_ms=record.get("latency_ms"),
                    extra_permission_violations=record.get("permission_violations"),
                )
                continue

            if not any(key in record for key in ("doc_id", "id", "chunk_id")):
                raise ValueError(f"{path}:{line_no}: expected results array or doc_id/id/chunk_id")
            grouped_rows.setdefault((method, qid), []).append(record)

    for (method, qid), hits in grouped_rows.items():
        sorted_hits = sorted(hits, key=_hit_sort_key)
        latency_values = [float(hit["latency_ms"]) for hit in sorted_hits if hit.get("latency_ms") is not None]
        runs.setdefault(method, {})[qid] = _query_from_hits(
            qid,
            sorted_hits,
            latency_ms=max(latency_values) if latency_values else None,
        )
    return runs


def load_named_agent_runs(run_args: list[str]) -> AgentRuns:
    merged: AgentRuns = {}
    for raw in run_args:
        forced_method, path = parse_run_arg(raw)
        runs = load_agent_run(path, forced_method or path.stem)
        for method, run in runs.items():
            merged[forced_method or method] = run
    return merged


def parse_run_arg(raw: str) -> tuple[str | None, Path]:
    if "=" in raw:
        method, path = raw.split("=", 1)
        if not method:
            raise ValueError("--run method=path must include a method name")
        return method, Path(path)
    return None, Path(raw)


def evaluate_agent_context(
    qrels: dict[str, dict[str, float]],
    runs: AgentRuns,
    ks: list[int],
    agent_queries: dict[str, AgentQuery] | None = None,
) -> dict[str, dict[str, float | int | None]]:
    agent_queries = agent_queries or {}
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
            row[f"context_recall@{k}"] = context_recall_at_k(qrels, run, k)
            row[f"citation_hit_rate@{k}"] = citation_hit_rate_at_k(qrels, run, k)
            row[f"tool_use_context_hit_rate@{k}"] = tool_use_context_hit_rate_at_k(agent_queries, run, k)
            row[f"permission_violation_rate@{k}"] = permission_violation_rate_at_k(agent_queries, run, k)
        summary[method] = row
    return summary


def context_recall_at_k(qrels: dict[str, dict[str, float]], run: dict[str, AgentRunQuery], k: int) -> float:
    values: list[float] = []
    for qid, labels in qrels.items():
        relevant = {doc_id for doc_id, rel in labels.items() if rel > 0}
        if not relevant:
            continue
        retrieved = set(_dedupe(run.get(qid, AgentRunQuery(qid)).doc_ids)[:k])
        values.append(len(relevant & retrieved) / len(relevant))
    return sum(values) / len(values) if values else 0.0


def citation_hit_rate_at_k(qrels: dict[str, dict[str, float]], run: dict[str, AgentRunQuery], k: int) -> float:
    values: list[float] = []
    for qid, labels in qrels.items():
        relevant = {doc_id for doc_id, rel in labels.items() if rel > 0}
        if not relevant:
            continue
        query = run.get(qid, AgentRunQuery(qid))
        citations = set(_dedupe(query.citation_ids or query.doc_ids)[:k])
        values.append(1.0 if relevant & citations else 0.0)
    return sum(values) / len(values) if values else 0.0


def tool_use_context_hit_rate_at_k(
    agent_queries: dict[str, AgentQuery],
    run: dict[str, AgentRunQuery],
    k: int,
) -> float | None:
    values: list[float] = []
    for qid, query_labels in agent_queries.items():
        required = query_labels.required_tool_context_ids
        if not required:
            continue
        query = run.get(qid, AgentRunQuery(qid))
        retrieved = set(_dedupe(query.tool_context_ids or query.doc_ids)[:k])
        values.append(1.0 if required & retrieved else 0.0)
    return (sum(values) / len(values)) if values else None


def permission_violation_rate_at_k(
    agent_queries: dict[str, AgentQuery],
    run: dict[str, AgentRunQuery],
    k: int,
) -> float:
    violations = 0
    total = 0
    for qid, query in run.items():
        top_docs = _dedupe(query.doc_ids)[:k]
        total += len(top_docs)
        violations += query.explicit_permission_violations
        allowed = agent_queries.get(qid, AgentQuery(qid)).allowed_doc_ids
        if allowed is not None:
            violations += sum(1 for doc_id in top_docs if doc_id not in allowed)
    return violations / total if total else 0.0


def markdown_report(summary: dict[str, dict[str, float | int | None]], ks: list[int]) -> str:
    headers = ["Method", "Queries"]
    for k in ks:
        headers.extend(
            [
                f"Context Recall@{k}",
                f"Citation Hit@{k}",
                f"Tool Context Hit@{k}",
                f"Permission Violation@{k}",
            ]
        )
    headers.extend(["P50 ms", "P95 ms", "P99 ms"])

    lines = [
        "# pg_retrieval_engine Agent Context Retrieval Benchmark",
        "",
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] + ["---:"] * (len(headers) - 1)) + " |",
    ]
    for method, row in summary.items():
        values = [method, str(row["queries"])]
        for k in ks:
            values.extend(
                [
                    fmt(row[f"context_recall@{k}"]),
                    fmt(row[f"citation_hit_rate@{k}"]),
                    fmt(row[f"tool_use_context_hit_rate@{k}"]),
                    fmt(row[f"permission_violation_rate@{k}"]),
                ]
            )
        values.extend([fmt(row["latency_p50_ms"]), fmt(row["latency_p95_ms"]), fmt(row["latency_p99_ms"])])
        lines.append("| " + " | ".join(values) + " |")

    lines.extend(
        [
            "",
            "Enterprise readiness gate: Permission Violation Rate must be 0.000000 for every production run.",
            "Recommended comparison set: dense-only, sparse-only, RRF, rerank, and optional FAISS candidate generation.",
        ]
    )
    return "\n".join(lines) + "\n"


def _query_from_hits(
    qid: str,
    hits: list[dict[str, Any]],
    *,
    latency_ms: Any = None,
    extra_permission_violations: Any = None,
) -> AgentRunQuery:
    query = AgentRunQuery(
        qid=qid,
        latency_ms=(float(latency_ms) if latency_ms is not None else None),
    )
    for hit in hits:
        doc_id = _doc_id_from_hit(hit)
        query.doc_ids.append(doc_id)
        query.citation_ids.append(str(hit.get("citation_id") or _citation_doc_id(hit) or doc_id))
        tool_context_id = hit.get("tool_context_id") or hit.get("context_id")
        if tool_context_id is not None:
            query.tool_context_ids.append(str(tool_context_id))
        if hit.get("permission_allowed") is False or hit.get("permission_violation") is True or hit.get("allowed") is False:
            query.explicit_permission_violations += 1

    if isinstance(extra_permission_violations, int):
        query.explicit_permission_violations += extra_permission_violations
    elif isinstance(extra_permission_violations, list):
        query.explicit_permission_violations += len(extra_permission_violations)
    return query


def _doc_id_from_hit(hit: dict[str, Any]) -> str:
    for key in ("doc_id", "id", "chunk_id"):
        if key in hit:
            return str(hit[key])
    raise ValueError(f"result hit has no doc_id/id/chunk_id field: {hit!r}")


def _citation_doc_id(hit: dict[str, Any]) -> str | None:
    citation = hit.get("citation")
    if isinstance(citation, dict):
        return citation.get("doc_id") or citation.get("source_uri")
    citation = hit.get("citation_metadata")
    if isinstance(citation, dict):
        return citation.get("doc_id") or citation.get("source_uri")
    return None


def _hit_sort_key(hit: dict[str, Any]) -> tuple[float, float, str]:
    rank = hit.get("rank")
    score = hit.get("score")
    if rank is not None:
        return (float(rank), 0.0, _doc_id_from_hit(hit))
    if score is not None:
        return (math.inf, -float(score), _doc_id_from_hit(hit))
    return (math.inf, 0.0, _doc_id_from_hit(hit))


def _dedupe(doc_ids: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for doc_id in doc_ids:
        if doc_id in seen:
            continue
        seen.add(doc_id)
        unique.append(doc_id)
    return unique


def fmt(value: float | int | None) -> str:
    if value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    return f"{value:.6f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Build an Agent context retrieval benchmark report.")
    parser.add_argument("--qrels", type=Path, required=True, help="TSV qrels: qid, context/citation doc_id, relevance")
    parser.add_argument("--agent-queries", type=Path, help="JSONL query metadata with allowed_doc_ids and required_tool_context_ids")
    parser.add_argument("--run", action="append", required=True, help="Run JSONL file, optionally named as method=path")
    parser.add_argument("--ks", default="10", help="comma-separated K values, for example 5,10")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--output", type=Path, help="optional output file")
    args = parser.parse_args()

    ks = parse_ks(args.ks)
    summary = evaluate_agent_context(
        load_qrels(args.qrels),
        load_named_agent_runs(args.run),
        ks,
        load_agent_queries(args.agent_queries),
    )
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
