# Benchmark

This document is the benchmark index. Module-specific quantitative test plans live under `docs/benchmark/`.

## Required Metrics

Every retrieval experiment must report:

- Recall@K
- NDCG@K
- average latency when relevant
- P95 latency
- P99 latency

RRF experiments must report vector-only, FTS-only, and RRF results on the same query set and qrels.

Agent context retrieval experiments must also report:

- Context Recall@K
- Citation Hit Rate@K
- Tool-use Context Hit Rate@K
- Permission Violation Rate@K, which must be `0`

## Module Benchmark Documents

| Module | Document |
|---|---|
| FAISS in PostgreSQL | [benchmark/faiss-in-pg.md](benchmark/faiss-in-pg.md) |
| RRF SQL | [benchmark/rrf-sql.md](benchmark/rrf-sql.md) |
| Agent context retrieval | [benchmark/agent-context-retrieval.md](benchmark/agent-context-retrieval.md) |
| Observability/autotune | [benchmark/observability-autotune.md](benchmark/observability-autotune.md) |
| Future modules | [benchmark/future-modules.md](benchmark/future-modules.md) |

Runner documentation: [benchmark-runner.md](benchmark-runner.md).

## Offline Evaluation

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

To generate a Markdown comparison report:

```bash
python3 bench/run_bench.py \
  --qrels evals/qrels.tsv \
  --run dense=results/dense.jsonl \
  --run fts=results/fts.jsonl \
  --run rrf=results/rrf.jsonl \
  --run rerank=results/rerank.jsonl \
  --run faiss=results/faiss.jsonl \
  --ks 10,20 \
  --output results/benchmark.md
```

Agent context retrieval benchmark:

```bash
python3 bench/run_agent_context_benchmark.py \
  --qrels evals/agent_qrels.tsv \
  --agent-queries evals/agent_queries.jsonl \
  --run rrf=evals/agent_sample_run.jsonl \
  --ks 5,10 \
  --output results/agent_context_benchmark.md
```

Run JSONL format:

```json
{"qid":"q1","method":"rrf","latency_ms":4.2,"results":[{"id":"d1"},{"id":"d2"}]}
```

## Current Recorded CPU Sample

Scale: `20,000 x 128`, `29` queries, `k=10`, local CPU batch path.

| Scenario | pgvector avg_ms | pg_retrieval_engine avg_ms | Speedup | pgvector Recall@10 | pg_retrieval_engine Recall@10 |
|---|---:|---:|---:|---:|---:|
| HNSW | 1.13 | 0.10 | 11.32x | 0.9552 | 1.0000 |
| IVFFlat | 0.76 | 0.07 | 10.31x | 1.0000 | 1.0000 |
