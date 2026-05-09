#!/usr/bin/env python3
"""Small Python search-tool wrapper for pg_retrieval_engine.

The wrapper intentionally stays thin: PostgreSQL owns retrieval execution, while
application or agent code receives structured rows and diagnostics.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, Sequence


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


@dataclass(frozen=True)
class RetrievalTrace:
    user_query: str
    retrieval_query: dict[str, Any]
    dense_topk: list[int]
    sparse_topk: list[int]
    rrf_overlap: int
    final_context: list[int]
    rerank_result: list[int] = field(default_factory=list)
    filtered_out_docs: list[int] = field(default_factory=list)
    likely_failure_reason: str | None = None
    raw_explain: Any = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_query": self.user_query,
            "retrieval_query": self.retrieval_query,
            "dense_topk": self.dense_topk,
            "sparse_topk": self.sparse_topk,
            "rrf_overlap": self.rrf_overlap,
            "rerank_result": self.rerank_result,
            "filtered_out_docs": self.filtered_out_docs,
            "final_context": self.final_context,
            "likely_failure_reason": self.likely_failure_reason,
            "raw_explain": self.raw_explain,
        }


@dataclass(frozen=True)
class ContextChunk:
    chunk_id: int
    document_id: int
    content: str
    context_content: str | None
    citation: dict[str, Any]
    metadata: dict[str, Any]
    scores: dict[str, Any]
    parent_chunk_id: int | None = None
    chunk_type: str = "child"
    explain: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "chunk_id": self.chunk_id,
            "document_id": self.document_id,
            "parent_chunk_id": self.parent_chunk_id,
            "chunk_type": self.chunk_type,
            "content": self.content,
            "context_content": self.context_content,
            "citation": self.citation,
            "metadata": self.metadata,
            "scores": self.scores,
            "explain": self.explain,
        }


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

    def search_chunks(
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

        if query_text is not None:
            tsquery_expr = "plainto_tsquery(%s, %s)"
            params = [
                vector_literal(query_vector),
                self.config.search_config,
                query_text,
                top_k,
                json.dumps(merged_options),
            ]
        else:
            tsquery_expr = "%s::tsquery"
            params = [
                vector_literal(query_vector),
                query_tsquery,
                top_k,
                json.dumps(merged_options),
            ]

        sql = f"""
            SELECT chunk_id, document_id, parent_chunk_id, chunk_type,
                   content, context_content, metadata, citation_metadata,
                   rrf_score, vector_rank, fts_rank, vector_distance, fts_score
            FROM pg_retrieval_engine_search_chunks(
                %s::vector,
                {tsquery_expr},
                %s::integer,
                %s::jsonb
            )
        """

        cursor = self.connection.cursor()
        try:
            cursor.execute(sql, params)
            columns = [column[0] for column in cursor.description]
            return [dict(zip(columns, row)) for row in cursor.fetchall()]
        finally:
            close = getattr(cursor, "close", None)
            if close is not None:
                close()


class AgentContextRetriever:
    """Agent-facing context retrieval API.

    ``PostgresHybridSearchTool`` remains the low-level SQL wrapper. This class is
    the application contract for RAG/agent workflows: it embeds a natural-language
    query, applies permission-aware retrieval options, and returns context chunks
    with citations, ranking diagnostics, and an optional retrieval trace.
    """

    def __init__(
        self,
        connection: Any,
        config: HybridSearchConfig,
        query_embedder: Callable[[str], Sequence[float]],
    ):
        self.search_tool = PostgresHybridSearchTool(connection, config)
        self.query_embedder = query_embedder
        self.last_trace: RetrievalTrace | None = None

    def retrieve_context(
        self,
        query: str,
        tenant_id: str | None = None,
        namespace: str | None = None,
        top_k: int = 10,
        filters: dict[str, Any] | None = None,
        explain: bool = False,
        *,
        user_id: str | None = None,
        agent_id: str | None = None,
        user_roles: Sequence[str] | None = None,
        allowed_roles: Sequence[str] | None = None,
        sensitivity_max: str | None = None,
    ) -> list[ContextChunk]:
        if query is None or query == "":
            raise ValueError("query must not be empty")
        if top_k < 1:
            raise ValueError("top_k must be >= 1")

        query_vector = self.query_embedder(query)
        options = build_agent_retrieval_options(
            default_options=self.search_tool.config.default_options,
            tenant_id=tenant_id,
            user_id=user_id,
            agent_id=agent_id,
            namespace=namespace,
            user_roles=user_roles,
            allowed_roles=allowed_roles,
            sensitivity_max=sensitivity_max,
            filters=filters,
        )
        options.setdefault("return_parent", True)

        rows = self.search_tool.search_chunks(
            query_vector,
            query_text=query,
            top_k=top_k,
            options=options,
        )
        trace = self._build_trace(query, top_k, options, rows, explain)
        self.last_trace = trace
        trace_dict = trace.to_dict() if trace is not None else None
        return [_context_chunk_from_row(row, trace_dict) for row in rows]

    def _build_trace(
        self,
        query: str,
        top_k: int,
        options: dict[str, Any],
        rows: list[dict[str, Any]],
        explain: bool,
    ) -> RetrievalTrace | None:
        if not explain:
            return None

        dense_topk = _ids_sorted_by_rank(rows, "vector_rank")
        sparse_topk = _ids_sorted_by_rank(rows, "fts_rank")
        final_context = [int(row["chunk_id"]) for row in rows]
        raw_explain = self.search_tool.explain(
            dense_topk,
            sparse_topk,
            final_context,
            options=options,
        )
        reason = raw_explain.get("likely_failure_reason") if isinstance(raw_explain, dict) else None
        return RetrievalTrace(
            user_query=query,
            retrieval_query={"query_text": query, "top_k": top_k, "options": options},
            dense_topk=dense_topk,
            sparse_topk=sparse_topk,
            rrf_overlap=len(set(dense_topk) & set(sparse_topk)),
            final_context=final_context,
            likely_failure_reason=reason,
            raw_explain=raw_explain,
        )


def build_agent_retrieval_options(
    *,
    default_options: dict[str, Any] | None = None,
    tenant_id: str | None = None,
    user_id: str | None = None,
    agent_id: str | None = None,
    namespace: str | None = None,
    user_roles: Sequence[str] | None = None,
    allowed_roles: Sequence[str] | None = None,
    sensitivity_max: str | None = None,
    filters: dict[str, Any] | None = None,
) -> dict[str, Any]:
    options = dict(default_options or {})
    scalar_filters = dict(options.get("filters") or {})
    if filters:
        scalar_filters.update(filters)
    if scalar_filters:
        options["filters"] = scalar_filters

    if tenant_id is not None:
        options["tenant_id"] = tenant_id
    if user_id is not None:
        options["user_id"] = user_id
    if agent_id is not None:
        options["agent_id"] = agent_id
    if namespace is not None:
        options["namespace"] = namespace
    if user_roles is not None:
        options["user_roles"] = list(user_roles)
    if allowed_roles is not None:
        options["allowed_roles"] = list(allowed_roles)
    if sensitivity_max is not None:
        options["sensitivity_max"] = sensitivity_max
    return options


def _ids_sorted_by_rank(rows: list[dict[str, Any]], rank_key: str) -> list[int]:
    ranked = [row for row in rows if row.get(rank_key) is not None]
    ranked.sort(key=lambda row: (int(row[rank_key]), int(row["chunk_id"])))
    return [int(row["chunk_id"]) for row in ranked]


def _context_chunk_from_row(row: dict[str, Any], trace: dict[str, Any] | None) -> ContextChunk:
    return ContextChunk(
        chunk_id=int(row["chunk_id"]),
        document_id=int(row["document_id"]),
        parent_chunk_id=(int(row["parent_chunk_id"]) if row.get("parent_chunk_id") is not None else None),
        chunk_type=str(row.get("chunk_type") or "child"),
        content=str(row.get("content") or ""),
        context_content=row.get("context_content"),
        citation=dict(row.get("citation_metadata") or {}),
        metadata=dict(row.get("metadata") or {}),
        scores={
            "rrf_score": row.get("rrf_score"),
            "vector_rank": row.get("vector_rank"),
            "fts_rank": row.get("fts_rank"),
            "vector_distance": row.get("vector_distance"),
            "fts_score": row.get("fts_score"),
        },
        explain=trace,
    )


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
