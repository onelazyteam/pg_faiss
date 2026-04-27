# Benchmark 方法论

状态：基准方法。

## 必须说明

- 数据集画像与规模。
- 查询集与 warmup 规则。
- 硬件与软件基线。
- 固定 qrels 下的 Recall@K 和 NDCG@K。
- vector、FTS、RRF 的 P95/P99 latency。
- 适用时与 pgvector 基线对比。

## 尾延迟

延迟以 query 级毫秒统计。RRF 延迟必须包含两路召回和 SQL 融合时间。
