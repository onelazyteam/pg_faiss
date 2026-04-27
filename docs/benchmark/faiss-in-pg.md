# Quantitative Test: FAISS in PostgreSQL

## Goal

Validate FAISS-backed ANN search against pgvector under the same dataset, query set, and recall constraint.

## Metrics

- Recall@10 and Recall@K for production K values
- average latency
- P95 latency
- P99 latency
- speedup vs pgvector

## Required Runs

| Run | Description |
|---|---|
| `pgvector_hnsw` | pgvector HNSW baseline |
| `pgvector_ivfflat` | pgvector IVFFlat baseline |
| `pg_retrieval_engine_hnsw` | FAISS HNSW path |
| `pg_retrieval_engine_ivfflat` | FAISS IVFFlat path |
| `pg_retrieval_engine_gpu_hnsw` | optional GPU path |

## Acceptance Targets

| Scenario | Target |
|---|---:|
| CPU speedup vs pgvector | `>= 5x` under target recall |
| GPU speedup vs pgvector | `>= 10x` under target recall |
| Recall@10 | `>= 0.95` unless the benchmark explicitly sets another threshold |

## Scripts

- `test/t/010_recall.pl`
- `test/t/020_perf_cpu_vs_pgvector.pl`
- `test/t/030_perf_gpu_vs_pgvector.pl`
- `test/bench/bench_cpu_batch_sample.sql`

## Current Recorded Sample

| Scenario | pgvector avg_ms | pg_retrieval_engine avg_ms | Speedup | pgvector Recall@10 | pg_retrieval_engine Recall@10 |
|---|---:|---:|---:|---:|---:|
| HNSW | 1.13 | 0.10 | 11.32x | 0.9552 | 1.0000 |
| IVFFlat | 0.76 | 0.07 | 10.31x | 1.0000 | 1.0000 |
