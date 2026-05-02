# Architecture

`pg_retrieval_engine` is designed as an in-PostgreSQL hybrid retrieval pipeline:

```text
application table
  ├── vector embedding  -> pgvector type / FAISS ANN query
  ├── tsvector          -> PostgreSQL full-text search
  └── metadata filters  -> SQL filters or ID allow-list

data preparation
  ├── documents         -> multi-source extracted text registry
  ├── chunks            -> parent-child chunks + citation metadata
  └── embedding jobs    -> versioned incremental vectorization queue

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
| Ingest/chunk/embedding queue | versioned SQL | multi-source text registry, chunks, metadata, embedding versions and jobs | implemented v1 |
| FAISS in PostgreSQL | `src/faiss_in_pg` | backend-local FAISS lifecycle and query execution | implemented |
| pgvector/FTS index helpers | versioned SQL | create pgvector HNSW/IVFFlat and `tsvector` GIN indexes | implemented v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | rank fusion for pgvector and `tsvector` results | implemented |
| FAISS + FTS hybrid | versioned SQL | FAISS dense and `tsvector` sparse retrieval before RRF | implemented v1 |
| Offline evaluation | `evals` | Recall@K, NDCG@K, P95/P99 latency evaluation | implemented |
| Observability/autotune | `src/faiss_in_pg` | runtime counters and search-parameter tuning | implemented |
| Rerank v1 | `src/fts_rerank` + versioned SQL | candidate reranking with external model/rule scores and citation metadata | implemented |
| Retrieval explain | versioned SQL | stage counts, overlap, and likely failure reason diagnostics | implemented v1 |
| disk graph | `src/disk_graph` | disk-oriented vector graph retrieval | planned |

## Runtime Boundaries

- FAISS indexes are backend-local PostgreSQL process objects and are not shared across sessions.
- The extension does not own application-table durability; PostgreSQL remains the source of truth.
- PDF/HTML/Markdown parsing and embedding model inference run outside PostgreSQL; the extension receives extracted text and vectors.
- RRF fusion is implemented in SQL/PLpgSQL so it can be iterated and evaluated independently.
- Cross-encoder and LLM inference for rerank runs outside PostgreSQL; the extension receives scores.
- Evaluation runs offline against exported JSONL run files.

## Documentation

- API: [api.md](api.md)
- Usage: [usage.md](usage.md)
- Benchmark: [benchmark.md](benchmark.md)
- Module design: [design.md](design.md)
