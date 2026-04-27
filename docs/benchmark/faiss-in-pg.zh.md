# 性能量化测试：FAISS in PostgreSQL

## 目标

在相同数据集、查询集、召回约束下，对比 FAISS 路径与 pgvector 基线。

## 指标

- Recall@10 以及生产 K 值对应的 Recall@K
- 平均延迟
- P95 latency
- P99 latency
- 相对 pgvector 的 speedup

## 必跑场景

| 场景 | 说明 |
|---|---|
| `pgvector_hnsw` | pgvector HNSW 基线 |
| `pgvector_ivfflat` | pgvector IVFFlat 基线 |
| `pg_retrieval_engine_hnsw` | FAISS HNSW 路径 |
| `pg_retrieval_engine_ivfflat` | FAISS IVFFlat 路径 |
| `pg_retrieval_engine_gpu_hnsw` | 可选 GPU 路径 |

## 验收目标

| 场景 | 目标 |
|---|---:|
| CPU 相对 pgvector speedup | 满足目标召回时 `>= 5x` |
| GPU 相对 pgvector speedup | 满足目标召回时 `>= 10x` |
| Recall@10 | 默认 `>= 0.95`，除非 benchmark 明确设置其它阈值 |

## 脚本

- `test/t/010_recall.pl`
- `test/t/020_perf_cpu_vs_pgvector.pl`
- `test/t/030_perf_gpu_vs_pgvector.pl`
- `test/bench/bench_cpu_batch_sample.sql`

## 当前样例结果

| 场景 | pgvector avg_ms | pg_retrieval_engine avg_ms | Speedup | pgvector Recall@10 | pg_retrieval_engine Recall@10 |
|---|---:|---:|---:|---:|---:|
| HNSW | 1.13 | 0.10 | 11.32x | 0.9552 | 1.0000 |
| IVFFlat | 0.76 | 0.07 | 10.31x | 1.0000 | 1.0000 |
