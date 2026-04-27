# Module Design: RRF SQL Fusion

## Scope

`src/rrf_sql` documents SQL/PLpgSQL functions installed by the extension SQL:

- `pg_retrieval_engine_rrf_fuse`
- `pg_retrieval_engine_hybrid_search`

This module intentionally stays outside the FAISS C++ implementation. It can be
changed, tested, and iterated without rebuilding FAISS bindings.

## RRF Formula

```text
score = vector_weight / (rrf_k + vector_rank)
      + fts_weight    / (rrf_k + fts_rank)
```

Ranks are 1-based. Missing ranks contribute `0`.

## `pg_retrieval_engine_rrf_fuse`

Input is two relevance-ordered ID arrays:

- `vector_ids bigint[]`
- `fts_ids bigint[]`

Duplicate IDs keep their best rank in each channel. Output is sorted by RRF
score, then best available rank, then ID for deterministic ties.

## `pg_retrieval_engine_hybrid_search`

Runs two independent subqueries over one table:

1. pgvector distance ranking over `vector_column`.
2. PostgreSQL `tsvector` ranking over `tsvector_column`.

The function fuses both candidate sets with RRF and returns:

```text
(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)
```

## Options

- `vector_k` / `dense_k`: vector candidate depth.
- `fts_k` / `sparse_k`: full-text candidate depth.
- `rrf_k`: RRF smoothing constant, default `60`.
- `vector_weight` / `dense_weight`: vector channel weight.
- `fts_weight` / `sparse_weight`: FTS channel weight.
- `vector_operator`: `<=>`, `<->`, or `<#>`.
- `rank_function`: `ts_rank_cd` or `ts_rank`.
- `normalization`: FTS normalization bitmask.

## Validation

The required acceptance comparison is:

- vector-only run
- FTS-only run
- RRF run

Each run must report Recall@K, NDCG@K, P95 latency, and P99 latency under the
same queries and qrels.

Performance test document: [../benchmark/rrf-sql.md](../benchmark/rrf-sql.md).
