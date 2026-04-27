# 可观测性

当前可观测性主要由 FAISS-in-PG runtime stats 提供。

## 接口

- `pg_retrieval_engine_index_stats(name)`
- `pg_retrieval_engine_metrics_reset(name default null)`

## 指标

- 调用量：`train_calls`、`add_calls`、`search_single_calls`、`search_batch_calls`、`search_filtered_calls`
- 数据量：`add_vectors_total`、`search_query_total`、`search_result_total`
- 耗时：`search_single_ms_total`、`search_batch_ms_total`、`search_filtered_ms_total`
- 运维：`save_calls`、`load_calls`、`autotune_calls`、`error_calls`
- 最近参数：`last_candidate_k`、`last_batch_size`、`preferred_batch_size`、`last_autotune_mode`

## 验证

可观测指标用于定位运行状态；是否接受参数调整仍需通过 Recall@K、NDCG@K、P95/P99 latency 验证。
