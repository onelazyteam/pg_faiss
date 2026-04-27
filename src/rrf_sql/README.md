# rrf_sql

Status: implemented as SQL/PLpgSQL extension functions.

Implemented scope:
- `pg_retrieval_engine_rrf_fuse`: fuse two ranked ID arrays with Reciprocal Rank Fusion.
- `pg_retrieval_engine_hybrid_search`: run pgvector vector ranking and PostgreSQL `tsvector`
  ranking against one table, then merge both result sets with RRF.

RRF score:

```text
score = vector_weight / (rrf_k + vector_rank)
      + fts_weight    / (rrf_k + fts_rank)
```

Ranks are 1-based. Missing ranks contribute `0`.
