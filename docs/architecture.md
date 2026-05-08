# Architecture

`pg_retrieval_engine` is designed as a PostgreSQL-native hybrid search engine. pgvector is the production-consistent dense retrieval path; FAISS is an optional backend-local accelerator for candidate generation and benchmarking.

```text
application table
  ├── vector embedding  -> pgvector HNSW / IVFFlat (primary)
  ├── optional FAISS    -> candidate accelerator with row recheck
  ├── tsvector          -> PostgreSQL full-text search
  └── filters           -> scalar filters / JSONB metadata / soft delete

data preparation
  ├── documents         -> multi-source extracted text registry
  ├── chunks            -> parent-child chunks + citation metadata
  └── embedding jobs    -> versioned incremental vectorization queue

retrieval results
  ├── dense ranking
  ├── sparse ranking
  ├── PostgreSQL row recheck
  └── RRF fusion ranking / optional rerank

evaluation and observability
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## Modules

| Module | Path | Responsibility | Status |
|---|---|---|---|
| Ingest/chunk/embedding queue | versioned SQL | multi-source text registry, chunks, metadata, embedding versions and jobs | implemented v1 |
| pgvector/FTS hybrid search | versioned SQL | production-consistent dense+sparse retrieval, filters, and RRF fusion | implemented |
| FAISS in PostgreSQL | `src/faiss_in_pg` | optional backend-local FAISS lifecycle and query execution | optional accelerator |
| pgvector/FTS index helpers | versioned SQL | create pgvector HNSW/IVFFlat and `tsvector` GIN indexes | implemented v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | rank fusion for pgvector and `tsvector` results | implemented |
| Metadata and row filters | versioned SQL | scalar filters, JSONB metadata filters, soft-delete filters, and FAISS row recheck | implemented v1 |
| FAISS + FTS hybrid | versioned SQL | FAISS candidates plus `tsvector` sparse retrieval before RRF, with PostgreSQL row recheck | implemented v1 |
| Offline evaluation | `evals` | Recall@K, NDCG@K, P95/P99 latency evaluation | implemented |
| Benchmark runner | `bench` | dense/FTS/RRF/rerank/FAISS comparison reports from exported run files | implemented v1 |
| Search tool API | `sdk/python` | thin application/agent wrapper for hybrid search | implemented v1 |
| Observability/autotune | versioned SQL + `src/faiss_in_pg` | explain diagnostics, hybrid knob recommendations, and FAISS runtime counters | implemented |
| Rerank v1 | `src/fts_rerank` + versioned SQL | candidate reranking with external model/rule scores and citation metadata | implemented |
| Retrieval explain | versioned SQL | stage counts, overlap, filters, latency hints, and likely failure reason diagnostics | implemented v1 |
| disk graph | `src/disk_graph` | disk-oriented vector graph retrieval | planned |

## Runtime Boundaries

- pgvector and PostgreSQL tables are the production-consistent source of truth.
- FAISS indexes are backend-local PostgreSQL process objects and are not shared across sessions; use them only as optional candidate accelerators.
- FAISS hybrid search joins candidate IDs back to PostgreSQL rows before fusion so filters and row visibility can be enforced.
- PDF/HTML/Markdown parsing and embedding model inference run outside PostgreSQL; the extension receives extracted text and vectors.
- RRF fusion is implemented in SQL/PLpgSQL so it can be iterated and evaluated independently.
- Cross-encoder and LLM inference for rerank runs outside PostgreSQL; the extension receives scores.
- Evaluation runs offline against exported JSONL run files.

## Documentation

- API: [api.md](api.md)
- Usage: [usage.md](usage.md)
- Benchmark: [benchmark.md](benchmark.md)
- Module design: [design.md](design.md)
