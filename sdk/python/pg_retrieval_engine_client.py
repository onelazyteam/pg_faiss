#!/usr/bin/env python3
"""Small Python search-tool wrapper for pg_retrieval_engine.

The wrapper intentionally stays thin: PostgreSQL owns retrieval execution, while
application or agent code receives structured rows and diagnostics.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Iterable, Sequence


def vector_literal(values: Sequence[float]) -> str:
    if not values:
        raise ValueError("query_vector must not be empty")
    return "[" + ",".join(format(float(value), ".9g") for value in values) + "]"


@dataclass(frozen=True)
class HybridSearchConfig:
    table_name: str
    id_column: str = "id"
    vector_column: str = "embedding"
    tsvector_column: str = "search_vector"
    search_config: str = "simple"
    default_options: dict[str, Any] = field(default_factory=dict)


class PostgresHybridSearchTool:
    """Callable search tool for apps, RAG systems, and agents.

    The connection object only needs DB-API compatible ``cursor()``, ``execute``,
    and ``fetchall`` behavior. psycopg and psycopg2 both fit that contract.
    """

    def __init__(self, connection: Any, config: HybridSearchConfig):
        self.connection = connection
        self.config = config

    def search(
        self,
        query_vector: Sequence[float],
        *,
        query_text: str | None = None,
        query_tsquery: str | None = None,
        top_k: int = 10,
        options: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        if top_k < 1:
            raise ValueError("top_k must be >= 1")
        if (query_text is None) == (query_tsquery is None):
            raise ValueError("provide exactly one of query_text or query_tsquery")

        merged_options = dict(self.config.default_options)
        if options:
            merged_options.update(options)

        sql, params = build_hybrid_search_sql(
            self.config,
            use_plain_text=query_text is not None,
        )
        params = [
            self.config.table_name,
            self.config.id_column,
            self.config.vector_column,
            self.config.tsvector_column,
            vector_literal(query_vector),
            self.config.search_config if query_text is not None else query_tsquery,
            query_text if query_text is not None else top_k,
            top_k if query_text is not None else json.dumps(merged_options),
            json.dumps(merged_options) if query_text is not None else None,
        ]
        params = [param for param in params if param is not None]

        cursor = self.connection.cursor()
        try:
            cursor.execute(sql, params)
            columns = [column[0] for column in cursor.description]
            return [dict(zip(columns, row)) for row in cursor.fetchall()]
        finally:
            close = getattr(cursor, "close", None)
            if close is not None:
                close()

    def explain(
        self,
        vector_ids: Iterable[int],
        fts_ids: Iterable[int],
        final_ids: Iterable[int],
        *,
        relevant_ids: Iterable[int] | None = None,
        options: dict[str, Any] | None = None,
    ) -> Any:
        cursor = self.connection.cursor()
        try:
            cursor.execute(
                """
                SELECT pg_retrieval_engine_retrieval_explain(
                    %s::bigint[],
                    %s::bigint[],
                    %s::bigint[],
                    %s::bigint[],
                    %s::jsonb
                )
                """,
                [
                    list(vector_ids),
                    list(fts_ids),
                    list(final_ids),
                    list(relevant_ids) if relevant_ids is not None else None,
                    json.dumps(options or {}),
                ],
            )
            return cursor.fetchone()[0]
        finally:
            close = getattr(cursor, "close", None)
            if close is not None:
                close()


def build_hybrid_search_sql(config: HybridSearchConfig, *, use_plain_text: bool) -> tuple[str, list[Any]]:
    if use_plain_text:
        tsquery_expr = "plainto_tsquery(%s, %s)"
    else:
        tsquery_expr = "%s::tsquery"

    sql = f"""
        SELECT id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score
        FROM pg_retrieval_engine_hybrid_search(
            %s::regclass,
            %s::name,
            %s::name,
            %s::name,
            %s::vector,
            {tsquery_expr},
            %s::integer,
            %s::jsonb
        )
    """
    return sql, []

