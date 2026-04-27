# Benchmark 文档

本文是 benchmark 入口。各模块的性能量化测试方案放在 `docs/benchmark/` 下。

## 必报指标

每次检索实验必须报告：

- Recall@K
- NDCG@K
- 必要时报告平均延迟
- P95 latency
- P99 latency

RRF 实验必须在同一 query set 和 qrels 下同时报告 vector-only、FTS-only、RRF 三组结果。

## 模块 Benchmark 文档

| 模块 | 文档 |
|---|---|
| FAISS in PostgreSQL | [benchmark/faiss-in-pg.zh.md](benchmark/faiss-in-pg.zh.md) |
| RRF SQL | [benchmark/rrf-sql.zh.md](benchmark/rrf-sql.zh.md) |
| 可观测性/自动调参 | [benchmark/observability-autotune.zh.md](benchmark/observability-autotune.zh.md) |
| 后续模块 | [benchmark/future-modules.zh.md](benchmark/future-modules.zh.md) |

## 离线评测

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

run JSONL 格式：

```json
{"qid":"q1","method":"rrf","latency_ms":4.2,"results":[{"id":"d1"},{"id":"d2"}]}
```

## 当前 CPU 样例结果

规模：`20,000 x 128`，`29` queries，`k=10`，本机 CPU batch 路径。

| 场景 | pgvector avg_ms | pg_retrieval_engine avg_ms | Speedup | pgvector Recall@10 | pg_retrieval_engine Recall@10 |
|---|---:|---:|---:|---:|---:|
| HNSW | 1.13 | 0.10 | 11.32x | 0.9552 | 1.0000 |
| IVFFlat | 0.76 | 0.07 | 10.31x | 1.0000 | 1.0000 |
