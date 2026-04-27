# 性能量化测试：RRF SQL 融合

## 目标

验证 RRF 是否能带来足够的混合检索质量收益，并明确 SQL 融合带来的延迟成本。

## 指标

- Recall@K
- NDCG@K
- P95 latency
- P99 latency

## 必做消融

| 结果集 | 说明 |
|---|---|
| `vector` | pgvector-only dense ranking |
| `fts` | PostgreSQL `tsvector` 全文 ranking |
| `rrf` | `pg_retrieval_engine_hybrid_search` 融合 ranking |

三组实验必须使用同一 query set、qrels、K 值和延迟测量口径。

## 命令

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## 验收规则

满足以下任一条件才接受 RRF：

- Recall@K 或 NDCG@K 相比两个单通道基线有提升，且延迟在预算内。
- RRF 与最佳单通道质量持平，但在不同 query 类型上稳定性更好。

目标 workload 下 P95/P99 latency 必须在服务预算内。
