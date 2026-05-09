# Search Tool API

状态：已在 `sdk/python/pg_retrieval_engine_client.py` 中实现。

底层 search tool 保持很薄：PostgreSQL 负责 dense 召回、sparse 召回、过滤和 RRF；应用代码只接收结构化结果。`search(...)` 面向业务表，`search_chunks(...)` 面向扩展托管的 chunks，并返回 content、parent context、metadata、citation 和 ranking diagnostics。

Agent workflow 应使用 `AgentContextRetriever.retrieve_context(...)`。它通过调用方提供的 embedder 生成 query embedding，构造权限感知检索 options，调用 managed chunk search，并返回带 citation、score 和可选 retrieval trace 的 `ContextChunk`。

## 示例

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
    filters={"doc_type": "runbook"},
    explain=True,
    user_id="alice",
    agent_id="dba-copilot",
    user_roles=["dba"],
    sensitivity_max="internal",
)
```

生成的检索 options 包含：

```json
{
  "tenant_id": "acme",
  "agent_id": "dba-copilot",
  "user_id": "alice",
  "user_roles": ["dba"],
  "namespace": "postgres_runbook",
  "sensitivity_max": "internal"
}
```

Agent RAG 不能只按相似度召回。Tenant、user、agent、role、namespace 和 sensitivity filter 是检索契约的一部分，传给 LLM 的上下文本身就必须经过权限过滤。

`explain=True` 时，每个 `ContextChunk` 会带 trace：

- user query 与 retrieval options
- fused result 中可见的 dense top K
- fused result 中可见的 sparse top K
- RRF overlap
- final context IDs
- 原始 `pg_retrieval_engine_retrieval_explain(...)` 输出

## 边界

- wrapper 不调用 LLM 或 rerank 服务。
- `PostgresHybridSearchTool` 不生成 embedding；调用方传入 `query_vector`。
- `AgentContextRetriever` 只通过调用方提供的 `query_embedder` 生成 embedding。
- SQL 保持参数化。表名和列名通过扩展的 `regclass` / `name` 参数传入。
