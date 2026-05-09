#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "sdk" / "python"))

from pg_retrieval_engine_client import (  # noqa: E402
    AgentContextRetriever,
    ContextChunk,
    HybridSearchConfig,
    PostgresHybridSearchTool,
    build_agent_retrieval_options,
    build_hybrid_search_sql,
    vector_literal,
)


class FakeCursor:
    def __init__(self) -> None:
        self.executed = None
        self.executions = []
        self.closed = False
        self.description = [("id",), ("rrf_score",), ("vector_rank",), ("fts_rank",), ("vector_distance",), ("fts_score",)]
        self.rows = [(1, 0.5, 1, 2, 0.1, 0.9)]
        self.one = None

    def execute(self, sql, params) -> None:
        self.executed = (sql, params)
        self.executions.append((sql, params))
        if "pg_retrieval_engine_search_chunks" in sql:
            self.description = [
                ("chunk_id",),
                ("document_id",),
                ("parent_chunk_id",),
                ("chunk_type",),
                ("content",),
                ("context_content",),
                ("metadata",),
                ("citation_metadata",),
                ("rrf_score",),
                ("vector_rank",),
                ("fts_rank",),
                ("vector_distance",),
                ("fts_score",),
            ]
            self.rows = [(1, 10, None, "child", "chunk", "parent", {"namespace": "postgres_runbook"}, {"source_uri": "file:///runbook.md"}, 0.5, 1, 2, 0.1, 0.9)]
        elif "pg_retrieval_engine_retrieval_explain" in sql:
            self.one = ({
                "stage_counts": {"vector": 1, "fts": 1, "final": 1, "overlap": 1},
                "likely_failure_reason": "no_relevance_labels",
            },)

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.one

    def close(self) -> None:
        self.closed = True


class FakeConnection:
    def __init__(self) -> None:
        self.cursor_obj = FakeCursor()

    def cursor(self):
        return self.cursor_obj


class SearchToolTests(unittest.TestCase):
    def test_vector_literal(self) -> None:
        self.assertEqual(vector_literal([1, 0.25, 3]), "[1,0.25,3]")
        with self.assertRaises(ValueError):
            vector_literal([])

    def test_build_hybrid_search_sql_plain_text(self) -> None:
        sql, _ = build_hybrid_search_sql(HybridSearchConfig(table_name="docs"), use_plain_text=True)
        self.assertIn("pg_retrieval_engine_hybrid_search", sql)
        self.assertIn("plainto_tsquery", sql)

    def test_search_executes_parameterized_sql(self) -> None:
        conn = FakeConnection()
        tool = PostgresHybridSearchTool(
            conn,
            HybridSearchConfig(
                table_name="docs",
                default_options={"vector_k": 20, "filters": {"tenant_id": "acme"}},
            ),
        )

        rows = tool.search([1, 0, 0], query_text="vector database", top_k=5)

        self.assertEqual(rows[0]["id"], 1)
        sql, params = conn.cursor_obj.executed
        self.assertIn("plainto_tsquery", sql)
        self.assertEqual(params[0], "docs")
        self.assertEqual(params[4], "[1,0,0]")
        self.assertEqual(params[6], "vector database")
        self.assertIn('"tenant_id": "acme"', params[-1])
        self.assertTrue(conn.cursor_obj.closed)

    def test_search_chunks_executes_managed_chunk_api(self) -> None:
        conn = FakeConnection()
        tool = PostgresHybridSearchTool(
            conn,
            HybridSearchConfig(table_name="ignored", default_options={"tenant_id": "acme"}),
        )

        rows = tool.search_chunks([1, 0, 0], query_text="vector database", top_k=3, options={"return_parent": True})

        self.assertEqual(rows[0]["chunk_id"], 1)
        sql, params = conn.cursor_obj.executed
        self.assertIn("pg_retrieval_engine_search_chunks", sql)
        self.assertEqual(params[0], "[1,0,0]")
        self.assertEqual(params[2], "vector database")
        self.assertIn('"return_parent": true', params[-1])
        self.assertIn('"tenant_id": "acme"', params[-1])

    def test_build_agent_retrieval_options(self) -> None:
        options = build_agent_retrieval_options(
            default_options={"vector_k": 20, "filters": {"status": "published"}},
            tenant_id="acme",
            user_id="alice",
            agent_id="dba-copilot",
            namespace="postgres_runbook",
            user_roles=["dba"],
            sensitivity_max="internal",
            filters={"doc_type": "manual"},
        )

        self.assertEqual(options["tenant_id"], "acme")
        self.assertEqual(options["agent_id"], "dba-copilot")
        self.assertEqual(options["user_roles"], ["dba"])
        self.assertEqual(options["namespace"], "postgres_runbook")
        self.assertEqual(options["sensitivity_max"], "internal")
        self.assertEqual(options["filters"]["status"], "published")
        self.assertEqual(options["filters"]["doc_type"], "manual")

    def test_agent_context_retriever_returns_chunks_with_trace(self) -> None:
        conn = FakeConnection()
        retriever = AgentContextRetriever(
            conn,
            HybridSearchConfig(table_name="ignored", default_options={"vector_k": 20}),
            query_embedder=lambda query: [1, 0, 0],
        )

        chunks = retriever.retrieve_context(
            "how to fix replication lag",
            tenant_id="acme",
            namespace="postgres_runbook",
            top_k=3,
            filters={"doc_type": "manual"},
            explain=True,
            user_id="alice",
            agent_id="dba-copilot",
            user_roles=["dba"],
            sensitivity_max="internal",
        )

        self.assertIsInstance(chunks[0], ContextChunk)
        self.assertEqual(chunks[0].chunk_id, 1)
        self.assertEqual(chunks[0].citation["source_uri"], "file:///runbook.md")
        self.assertEqual(chunks[0].scores["vector_rank"], 1)
        self.assertEqual(chunks[0].explain["likely_failure_reason"], "no_relevance_labels")
        self.assertEqual(retriever.last_trace.final_context, [1])
        self.assertIn("pg_retrieval_engine_search_chunks", conn.cursor_obj.executions[0][0])
        self.assertIn("pg_retrieval_engine_retrieval_explain", conn.cursor_obj.executions[1][0])
        search_options = conn.cursor_obj.executions[0][1][-1]
        self.assertIn('"tenant_id": "acme"', search_options)
        self.assertIn('"agent_id": "dba-copilot"', search_options)


if __name__ == "__main__":
    unittest.main()
