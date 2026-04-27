# Quantitative Test: Future Modules

## Scope

This document defines the benchmark contract for planned modules such as `disk_graph` and `fts_rerank`.

## Required Before Implementation

Every new module must define:

- baseline module
- target dataset scale
- query set
- qrels format
- Recall@K target
- NDCG@K target when relevance is graded
- P95/P99 latency budget
- export format compatible with `evals/run_eval.py`

## Required Report

New modules must be reported alongside existing baselines:

- FAISS path
- pgvector path where applicable
- FTS path where applicable
- RRF path where applicable
