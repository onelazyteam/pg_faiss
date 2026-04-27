# 模块设计：RRF SQL 融合

## 范围

`src/rrf_sql` 记录 SQL/PLpgSQL 融合层设计，运行函数由扩展 SQL 安装：

- `pg_retrieval_engine_rrf_fuse`
- `pg_retrieval_engine_hybrid_search`

该模块不下沉到 FAISS C++ 路径，便于独立迭代、测试和调参。

## 公式

```text
score = vector_weight / (rrf_k + vector_rank)
      + fts_weight    / (rrf_k + fts_rank)
```

rank 从 1 开始；某通道缺失时贡献为 `0`。

## 接口

`pg_retrieval_engine_rrf_fuse` 输入两个已按相关性排序的 ID 数组，输出融合排名。重复 ID 在每个通道内取最佳 rank。

`pg_retrieval_engine_hybrid_search` 在同一张表上执行两路召回：

1. pgvector 距离排序。
2. PostgreSQL `tsvector` 全文排序。

最终返回：

```text
(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)
```

## 验证

每次调 RRF 参数时，都要同时报告 vector-only、FTS-only、RRF 三组结果的 Recall@K、NDCG@K、P95 latency、P99 latency。

性能量化测试文档：[../benchmark/rrf-sql.zh.md](../benchmark/rrf-sql.zh.md)。
