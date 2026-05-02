# fts_rerank

Status: implemented as SQL rerank v1.

Implemented scope:
- `pg_retrieval_engine_rerank`: rerank an existing candidate ID list with externally supplied scores.
- Supported score channels: cross-encoder, LLM, rule-based, and base scores.
- Supported score normalization: `none` and `minmax`.

Execution boundary:
- Cross-encoder and LLM inference runs outside PostgreSQL.
- PostgreSQL receives score arrays and performs deterministic weighting, tie-breaking, and diagnostics.
