#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "sdk" / "python"))

from pg_retrieval_engine_client import (  # noqa: E402
    HybridSearchConfig,
    PostgresHybridSearchTool,
    build_hybrid_search_sql,
    vector_literal,
)


class FakeCursor:
    description = [("id",), ("rrf_score",), ("vector_rank",), ("fts_rank",), ("vector_distance",), ("fts_score",)]

    def __init__(self) -> None:
        self.executed = None
        self.closed = False

    def execute(self, sql, params) -> None:
        self.executed = (sql, params)

    def fetchall(self):
        return [(1, 0.5, 1, 2, 0.1, 0.9)]

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


if __name__ == "__main__":
    unittest.main()

