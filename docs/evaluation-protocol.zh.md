# 评测协议

状态：已由 `evals/` 离线脚本支持。

## 必报结果

每次融合实验必须报告：

- Recall@K
- NDCG@K
- P95 latency
- P99 latency

vector-only、FTS-only、RRF 必须使用同一 query set 和 qrels。

## 命令

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

使用 `--json` 可输出适合 CI 或 dashboard 消费的 JSON。

## 格式

qrels：

```text
qid<TAB>doc_id<TAB>relevance
```

run JSONL：

```json
{"qid":"q1","method":"rrf","latency_ms":4.2,"results":[{"id":"d1"},{"id":"d2"}]}
```

也支持 row-level run JSONL：

```json
{"qid":"q1","method":"rrf","doc_id":"d1","rank":1,"latency_ms":4.2}
```
