# 模块设计：可观测性与自动调参

## 范围

当前可观测性与自动调参主要覆盖 FAISS 运行路径。

## 运行指标

`pg_retrieval_engine_index_stats(name)` 暴露：

- 调用计数：train、add、single search、batch search、filtered search。
- 数据量计数：写入向量数、查询数、输出结果数。
- 各查询路径耗时总量与平均值。
- 最近运行参数：`last_candidate_k`、`last_batch_size`。
- 自动调参状态：`preferred_batch_size`、`last_autotune_mode`。

`pg_retrieval_engine_metrics_reset(name default null)` 可重置单索引或当前 backend 的全部索引指标。

## 自动调参

`pg_retrieval_engine_index_autotune(name, mode, options)` 会更新默认搜索参数：

- HNSW：`ef_search`
- IVF/IVFPQ：`nprobe`
- batch 路径：`preferred_batch_size`

模式包括 `latency`、`balanced`、`recall`。

## 验证

自动调参前后都要按统一评测协议报告 Recall@K、NDCG@K、P95 latency、P99 latency，避免只看延迟或只看召回。

性能量化测试文档：[../benchmark/observability-autotune.zh.md](../benchmark/observability-autotune.zh.md)。
