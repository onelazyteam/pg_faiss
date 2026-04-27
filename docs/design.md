# pg_retrieval_engine Design Index

The project is split into mostly independent modules. Keep detailed design notes
next to the module they describe, and keep this file as the top-level map.

## Module Design Documents

| Module | Document | Runtime status |
|---|---|---|
| FAISS in PostgreSQL | [design/faiss-in-pg.md](design/faiss-in-pg.md) | implemented |
| RRF SQL fusion | [design/rrf-sql.md](design/rrf-sql.md) | implemented |
| Evaluation metrics | [design/evaluation.md](design/evaluation.md) | implemented offline |
| Observability and autotune | [design/observability-autotune.md](design/observability-autotune.md) | implemented for FAISS path |
| Future modules | [design/future-modules.md](design/future-modules.md) | scaffold |

## Release Checklist

1. Update both fresh-install SQL and upgrade SQL.
2. Run `make clean all`, `make install`, and `make installcheck`.
3. Run offline evaluation with Recall@K, NDCG@K, P95 latency, and P99 latency for vector, FTS, and RRF runs.
4. Keep README/API/design docs aligned in English and Chinese.
