# Search Tool API

状态：已在 `sdk/python/pg_retrieval_engine_client.py` 中实现为轻量 Python wrapper。

这个 search tool 保持很薄：PostgreSQL 负责 dense 召回、sparse 召回、过滤和 RRF；应用或 Agent 代码只接收结构化结果。

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
            "filters": {"tenant_id": "acme"},
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
```

## 边界

- wrapper 不调用 LLM 或 rerank 服务。
- wrapper 不生成 embedding；调用方传入 `query_vector`。
- SQL 保持参数化。表名和列名通过扩展的 `regclass` / `name` 参数传入。

