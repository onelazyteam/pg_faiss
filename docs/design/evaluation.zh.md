# 模块设计：评测指标

## 范围

`evals` 负责离线评测，不直接连接 PostgreSQL。SQL 或 benchmark 脚本先导出 JSONL 结果，再由 `evals/run_eval.py` 统一计算指标。

## 必报指标

- `Recall@K`：top K 内召回相关文档的比例。
- `NDCG@K`：考虑 graded relevance 的排序质量。
- `latency_p95_ms`：query 级 P95 延迟。
- `latency_p99_ms`：query 级 P99 延迟。

示例：

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## qrels 格式

```text
qid<TAB>doc_id<TAB>relevance
```

`relevance > 0` 计入 Recall@K；NDCG@K 使用 relevance 的分级值。

## run JSONL 格式

推荐 query 级格式：

```json
{"qid":"q1","method":"rrf","latency_ms":4.2,"results":[{"id":"d1"},{"id":"d2"}]}
```

也支持 row 级格式：

```json
{"qid":"q1","method":"rrf","doc_id":"d1","rank":1,"latency_ms":4.2}
```
