# 性能量化测试：可观测性与自动调参

## 目标

验证 runtime counters 是否足够支撑运维判断，并确认自动调参能改善延迟/召回权衡且没有隐藏回归。

## 指标

- `search_single_calls`
- `search_batch_calls`
- `search_filtered_calls`
- `search_query_total`
- `search_result_total`
- 各查询路径平均延迟
- autotune 前后的 Recall@K
- autotune 前后的 P95/P99 latency

## 必做对比

| 结果集 | 说明 |
|---|---|
| `before_autotune` | 默认参数或当前生产参数 |
| `latency` | 执行 `pg_retrieval_engine_index_autotune(..., 'latency', ...)` 后 |
| `balanced` | 执行 `pg_retrieval_engine_index_autotune(..., 'balanced', ...)` 后 |
| `recall` | 执行 `pg_retrieval_engine_index_autotune(..., 'recall', ...)` 后 |

## 验收规则

自动调参不能只看延迟 counters 接受。必须基于固定 qrels 同时验证 Recall@K、NDCG@K、P95 latency、P99 latency。
