# Module Design: Observability and Autotune

## Scope

Observability and autotune currently apply to the FAISS runtime path.

## Runtime Metrics

`pg_retrieval_engine_index_stats(name)` exposes:

- call counters: train, add, single search, batch search, filtered search
- volume counters: added vectors, searched queries, emitted results
- latency totals and averages by search path
- latest runtime knobs: `last_candidate_k`, `last_batch_size`
- autotune state: `preferred_batch_size`, `last_autotune_mode`

`pg_retrieval_engine_metrics_reset(name default null)` resets one index or all
backend-local indexes.

## Autotune

`pg_retrieval_engine_index_autotune(name, mode, options)` updates default FAISS
search knobs:

- HNSW: `ef_search`
- IVF/IVFPQ: `nprobe`
- batch path: `preferred_batch_size`

Modes:

- `latency`
- `balanced`
- `recall`

## Validation

Autotune changes must be validated with the same offline evaluation protocol as
RRF changes. Report Recall@K, NDCG@K, P95 latency, and P99 latency before and
after changing defaults.

Performance test document: [../benchmark/observability-autotune.md](../benchmark/observability-autotune.md).
