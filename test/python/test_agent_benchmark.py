#!/usr/bin/env python3

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bench"))

from run_agent_context_benchmark import (  # noqa: E402
    AgentQuery,
    AgentRunQuery,
    evaluate_agent_context,
    load_agent_queries,
    load_agent_run,
)


class AgentBenchmarkTests(unittest.TestCase):
    def test_evaluate_agent_context_metrics(self) -> None:
        qrels = {"q1": {"runbook-1": 1.0}, "q2": {"tool-doc": 1.0}}
        runs = {
            "rrf": {
                "q1": AgentRunQuery(
                    qid="q1",
                    doc_ids=["runbook-1", "confidential-doc"],
                    citation_ids=["runbook-1", "confidential-doc"],
                    latency_ms=4.0,
                ),
                "q2": AgentRunQuery(
                    qid="q2",
                    doc_ids=["tool-doc"],
                    citation_ids=["tool-doc"],
                    tool_context_ids=["restart-tool-context"],
                    latency_ms=8.0,
                ),
            }
        }
        queries = {
            "q1": AgentQuery(qid="q1", allowed_doc_ids={"runbook-1"}),
            "q2": AgentQuery(
                qid="q2",
                allowed_doc_ids={"tool-doc"},
                required_tool_context_ids={"restart-tool-context"},
            ),
        }

        summary = evaluate_agent_context(qrels, runs, [1, 2], queries)

        self.assertEqual(summary["rrf"]["context_recall@1"], 1.0)
        self.assertEqual(summary["rrf"]["citation_hit_rate@1"], 1.0)
        self.assertEqual(summary["rrf"]["tool_use_context_hit_rate@1"], 1.0)
        self.assertEqual(summary["rrf"]["permission_violation_rate@1"], 0.0)
        self.assertGreater(summary["rrf"]["permission_violation_rate@2"], 0.0)
        self.assertEqual(summary["rrf"]["latency_p95_ms"], 8.0)

    def test_load_agent_jsonl_formats(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            queries_path = root / "agent_queries.jsonl"
            run_path = root / "agent_run.jsonl"
            queries_path.write_text(
                '{"qid":"q1","allowed_doc_ids":["runbook-1"],"required_tool_context_ids":["ctx-1"]}\n',
                encoding="utf-8",
            )
            run_path.write_text(
                '{"qid":"q1","method":"rrf","latency_ms":3.5,'
                '"results":[{"id":"runbook-1","citation_id":"runbook-1","tool_context_id":"ctx-1"}]}\n',
                encoding="utf-8",
            )

            queries = load_agent_queries(queries_path)
            runs = load_agent_run(run_path, "rrf")

        self.assertEqual(queries["q1"].allowed_doc_ids, {"runbook-1"})
        self.assertEqual(queries["q1"].required_tool_context_ids, {"ctx-1"})
        self.assertEqual(runs["rrf"]["q1"].doc_ids, ["runbook-1"])
        self.assertEqual(runs["rrf"]["q1"].citation_ids, ["runbook-1"])
        self.assertEqual(runs["rrf"]["q1"].tool_context_ids, ["ctx-1"])


if __name__ == "__main__":
    unittest.main()
