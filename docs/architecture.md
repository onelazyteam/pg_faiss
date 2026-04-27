# Architecture

`pg_retrieval_engine` is designed as an in-PostgreSQL hybrid retrieval pipeline:

```text
application table
  ├── vector embedding  -> pgvector type / FAISS ANN query
  ├── tsvector          -> PostgreSQL full-text search
  └── metadata filters  -> SQL filters or ID allow-list

retrieval results
  ├── dense ranking
  ├── sparse ranking
  └── RRF fusion ranking

evaluation and observability
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## Modules

| Module | Path | Responsibility | Status |
|---|---|---|---|
| FAISS in PostgreSQL | `src/faiss_in_pg` | backend-local FAISS lifecycle and query execution | implemented |
| RRF SQL | `src/rrf_sql` + versioned SQL | rank fusion for pgvector and `tsvector` results | implemented |
| Offline evaluation | `evals` | Recall@K, NDCG@K, P95/P99 latency evaluation | implemented |
| Observability/autotune | `src/faiss_in_pg` | runtime counters and search-parameter tuning | implemented |
| disk graph | `src/disk_graph` | disk-oriented vector graph retrieval | planned |
| FTS rerank | `src/fts_rerank` | richer sparse retrieval reranking | planned |

## Runtime Boundaries

- FAISS indexes are backend-local PostgreSQL process objects and are not shared across sessions.
- The extension does not own application-table durability; PostgreSQL remains the source of truth.
- RRF fusion is implemented in SQL/PLpgSQL so it can be iterated and evaluated independently.
- Evaluation runs offline against exported JSONL run files.

## Documentation

- API: [api.md](api.md)
- Usage: [usage.md](usage.md)
- Benchmark: [benchmark.md](benchmark.md)
- Module design: [design.md](design.md)
