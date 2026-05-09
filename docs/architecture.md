# Architecture

`pg_retrieval_engine` is designed as a PostgreSQL-native hybrid search engine. pgvector is the production-consistent dense retrieval path; FAISS is an optional backend-local accelerator for candidate generation and benchmarking.

```text
application table
  ├── vector embedding  -> pgvector HNSW / IVFFlat (primary)
  ├── optional FAISS    -> candidate accelerator with row recheck
  ├── tsvector          -> PostgreSQL full-text search
  └── filters           -> tenant / ACL / scalar filters / JSONB metadata / soft delete

data preparation
  ├── documents         -> tenant-scoped multi-source extracted text registry
  ├── chunks            -> stable parent-child chunks + citation metadata
  ├── embedding jobs    -> claimable versioned incremental vectorization queue
  └── chunk embeddings  -> one row per chunk and embedding model version

retrieval results
  ├── dense ranking
  ├── sparse ranking
  ├── PostgreSQL row recheck
  └── RRF fusion ranking / optional rerank / agent-ready chunk output

evaluation and observability
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## Modules

| Module | Path | Responsibility | Status |
|---|---|---|---|
| Ingest/chunk/embedding queue | versioned SQL | tenant-scoped text registry, stable chunk upsert, metadata, ACL, embedding versions and claimable jobs | implemented v2 |
| Versioned chunk embeddings | versioned SQL | stores embeddings by `(chunk_id, embedding_version_id)` while keeping the latest vector on chunks for compatibility | implemented v1 |
| pgvector/FTS hybrid search | versioned SQL | production-consistent dense+sparse retrieval, tenant/ACL filters, batch wrapper, and RRF fusion | implemented |
| FAISS in PostgreSQL | `src/faiss_in_pg` | optional backend-local FAISS lifecycle and query execution | optional accelerator |
| pgvector/FTS index helpers | versioned SQL | create pgvector HNSW/IVFFlat and `tsvector` GIN indexes | implemented v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | rank fusion for pgvector and `tsvector` results | implemented |
| Metadata, ACL, and row filters | versioned SQL | tenant, user, agent, role, namespace, sensitivity, scalar, JSONB metadata/ACL, soft-delete filters, and FAISS row recheck | implemented v3 |
| FAISS + FTS hybrid | versioned SQL | FAISS candidates plus `tsvector` sparse retrieval before RRF, with PostgreSQL row recheck | implemented v1 |
| Offline evaluation | `evals` | Recall@K, NDCG@K, P95/P99 latency evaluation | implemented |
| Benchmark runner | `bench` | dense/FTS/RRF/rerank/FAISS reports plus Agent context retrieval benchmark with permission-violation metrics | implemented v2 |
| Search tool API | `sdk/python` | low-level hybrid search wrapper plus Agent Context API returning context chunks, citations, scores, and retrieval traces | implemented v3 |
| Observability/autotune | versioned SQL + `src/faiss_in_pg` | explain diagnostics, hybrid knob recommendations, and FAISS runtime counters | implemented |
| Rerank v1 | `src/fts_rerank` + versioned SQL | candidate reranking with external model/rule scores and citation metadata | implemented |
| Retrieval explain | versioned SQL | stage counts, overlap, filters, latency hints, and likely failure reason diagnostics | implemented v1 |
| disk graph | `src/disk_graph` | disk-oriented vector graph retrieval | planned |

## Runtime Boundaries

- pgvector and PostgreSQL tables are the production-consistent source of truth.
- Extension-managed documents are scoped by `(tenant_id, source_uri)`. ACL data is stored as JSONB and can be applied as `acl_filter` during retrieval.
- Chunking uses stable upserts keyed by `(document_id, chunk_type, chunk_no)`. Existing chunk IDs are preserved when chunk positions are reused; changed content clears the latest embedding so workers can re-embed safely.
- Embedding workers should call `pg_retrieval_engine_claim_embedding_jobs(...)` to atomically lease work, then pass the returned `attempts` and `worker_id` into `pg_retrieval_engine_embedding_job_complete(...)` or `pg_retrieval_engine_embedding_job_fail(...)` for fenced writeback, state/content/dimension validation, and retry-safe failure handling.
- `pg_retrieval_engine_activate_embedding_version(...)` promotes one validated embedding version into the latest chunk vector column used by the production search path.
- FAISS indexes are backend-local PostgreSQL process objects and are not shared across sessions; use them only as optional candidate accelerators.
- FAISS hybrid search joins candidate IDs back to PostgreSQL rows before fusion so filters and row visibility can be enforced.
- PDF/HTML/Markdown parsing and embedding model inference run outside PostgreSQL; the extension receives extracted text and vectors.
- RRF fusion is implemented in SQL/PLpgSQL so it can be iterated and evaluated independently.
- Cross-encoder and LLM inference for rerank runs outside PostgreSQL; the extension receives scores.
- Evaluation runs offline against exported JSONL run files.

## Production Roadmap

- Keep pgvector/FTS as the durable retrieval path. Treat backend-local FAISS as an optional accelerator until a shared sidecar or PostgreSQL Index AM exists.
- Add tokenizer-aware and structure-aware chunkers outside the PostgreSQL backend, then feed stable chunks back through the SQL API.
- Add adaptive candidate retry for highly selective tenant/ACL filters, plus exact fallback when the filtered ANN candidate set is too small.
- Promote runtime counters to persistent `pg_stat`-style observability with per-tenant latency percentiles, filter drop rate, rerank latency, and trace IDs.

## Documentation

- API: [api.md](api.md)
- Usage: [usage.md](usage.md)
- Benchmark: [benchmark.md](benchmark.md)
- Module design: [design.md](design.md)
