# Search Tool API

Status: implemented as a thin Python wrapper in `sdk/python/pg_retrieval_engine_client.py`.

The search tool is intentionally small. PostgreSQL executes dense retrieval, sparse retrieval, filters, and RRF; application or agent code receives structured rows.

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

## Boundary

- The wrapper does not call LLMs or rerank services.
- The wrapper does not build embeddings; the caller supplies `query_vector`.
- SQL remains parameterized. Table and column names are passed to the extension as `regclass` / `name` arguments.

