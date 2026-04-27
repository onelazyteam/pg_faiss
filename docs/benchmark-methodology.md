# Benchmark Methodology

Status: baseline methodology.

## Required Dimensions

- Dataset profile and scale bucket.
- Query mix and warmup rules.
- Hardware/software baseline.
- Recall@K and NDCG@K against fixed qrels.
- P95/P99 latency for vector, FTS, and RRF.
- Comparison against pgvector baseline where applicable.

## Tail Latency

Report query-level latency in milliseconds. For RRF, include both retrieval
channels and SQL fusion time in the measured latency.
