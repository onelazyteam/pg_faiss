# Search Tool API

Status: implemented in `sdk/python/pg_retrieval_engine_client.py`.

The low-level search tool is intentionally small. PostgreSQL executes dense retrieval, sparse retrieval, filters, and RRF; application code receives structured rows. `search(...)` targets an application table, while `search_chunks(...)` targets extension-managed chunks and returns content, parent context, metadata, citations, and ranking diagnostics.

Agent workflows should use `AgentContextRetriever.retrieve_context(...)`. It embeds the natural-language query through a caller-provided embedder, builds permission-aware retrieval options, calls managed chunk search, and returns `ContextChunk` objects with citations, scores, and optional retrieval trace data.

## Example

```python
from pg_retrieval_engine_client import HybridSearchConfig, PostgresHybridSearchTool

tool = PostgresHybridSearchTool(
    connection,
    HybridSearchConfig(
        table_name="documents",
        id_column="id",
        vector_column="embedding",
        tsvector_column="search_vector",
        default_options={
            "vector_k": 100,
            "fts_k": 100,
            "tenant_id": "acme",
            "acl_filter": {"groups": ["support"]},
            "metadata_filter": {"doc_type": "manual"},
            "soft_delete_column": "deleted_at",
        },
    ),
)

rows = tool.search(
    [0.1, 0.2, 0.3, 0.4],
    query_text="vector database",
    top_k=10,
)

chunk_rows = tool.search_chunks(
    [0.1, 0.2, 0.3, 0.4],
    query_text="vector database",
    top_k=8,
    options={"return_parent": True},
)
```

## Agent Context API

```python
from pg_retrieval_engine_client import AgentContextRetriever, HybridSearchConfig

retriever = AgentContextRetriever(
    connection,
    HybridSearchConfig(
        table_name="pg_retrieval_engine_chunks",
        default_options={"vector_k": 100, "fts_k": 100},
    ),
    query_embedder=lambda text: embedding_model.embed(text),
)

chunks = retriever.retrieve_context(
    "how should I diagnose replication lag?",
    tenant_id="acme",
    namespace="postgres_runbook",
    top_k=10,
    metadata_filter={"doc_type": {"op": "in", "value": ["runbook", "postgres_docs"]}},
    explain=True,
    user_id="alice",
    agent_id="dba-copilot",
    user_roles=["dba"],
    sensitivity_max="internal",
)
```

The generated retrieval options include:

```json
{
  "tenant_id": "acme",
  "agent_id": "dba-copilot",
  "user_id": "alice",
  "user_roles": ["dba"],
  "namespace": "postgres_runbook",
  "sensitivity_max": "internal",
  "metadata_filter": {
    "doc_type": {"op": "in", "value": ["runbook", "postgres_docs"]}
  }
}
```

Agent RAG must not retrieve by similarity alone. Tenant, user, agent, role, namespace, and sensitivity filters are part of the retrieval contract so the context passed to an LLM is already permission-aware.

For Agent workflows that need multiple document types, use metadata operator filters:

```json
{
  "metadata_filter": {
    "doc_type": {"op": "in", "value": ["runbook", "postgres_docs"]}
  }
}
```

When `explain=True`, each `ContextChunk` includes a trace with:

- user query and retrieval options
- dense top K seen in the fused result
- sparse top K seen in the fused result
- RRF overlap
- final context IDs
- raw `pg_retrieval_engine_retrieval_explain(...)` output

## Boundary

- The wrapper does not call LLMs or rerank services.
- `PostgresHybridSearchTool` does not build embeddings; the caller supplies `query_vector`.
- `AgentContextRetriever` builds embeddings only through the caller-provided `query_embedder`.
- SQL remains parameterized. Table and column names are passed to the extension as `regclass` / `name` arguments.
