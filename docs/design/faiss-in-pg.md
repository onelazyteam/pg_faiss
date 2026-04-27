# Module Design: FAISS in PostgreSQL

## Scope

`src/faiss_in_pg` owns the backend-local FAISS runtime:

- Create, train, add, search, batch search, filtered search.
- Save/load FAISS indexes with sidecar metadata.
- CPU path and optional GPU path.
- Runtime counters exposed through `pg_retrieval_engine_index_stats`.

## API

- `pg_retrieval_engine_index_create`
- `pg_retrieval_engine_index_train`
- `pg_retrieval_engine_index_add`
- `pg_retrieval_engine_index_search`
- `pg_retrieval_engine_index_search_batch`
- `pg_retrieval_engine_index_search_filtered`
- `pg_retrieval_engine_index_search_batch_filtered`
- `pg_retrieval_engine_index_save`
- `pg_retrieval_engine_index_load`
- `pg_retrieval_engine_index_drop`
- `pg_retrieval_engine_reset`

## Execution Model

Indexes live in a backend-local hash table keyed by index name. They are not
shared across sessions and are not WAL-replayed. The caller owns durable source
data; this module owns fast runtime search over explicitly added vectors.

Single-query search applies per-call FAISS knobs, runs `index->search`, converts
cosine scores when needed, and returns `(id, distance)`.

Batch search chunks input queries by `batch_size` to bound memory:

```text
peak memory = O(batch_size * candidate_k)
```

Filtered search is implemented as candidate widening plus an ID allow-list. It
does not parse arbitrary SQL predicates inside the C++ extension.

## Validation

- Regression: lifecycle, search, batch search, filtered search, save/load.
- TAP: recall and CPU/GPU performance comparison against pgvector.
- Offline eval: export FAISS/vector results and compare Recall@K, NDCG@K, P95,
  and P99 latency against FTS and RRF runs.

Performance test document: [../benchmark/faiss-in-pg.md](../benchmark/faiss-in-pg.md).
