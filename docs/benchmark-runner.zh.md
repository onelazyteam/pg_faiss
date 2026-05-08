# Benchmark Runner

状态：已在 `bench/run_bench.py` 和 `bench/run_ablation.py` 中实现。

Benchmark runner 读取导出的 JSONL run 文件和固定 qrels，输出 Recall@K、NDCG@K 以及 P50/P95/P99 latency。

## 标准报告

```bash
python3 bench/run_bench.py \
  --qrels evals/qrels.tsv \
  --run dense=results/dense.jsonl \
  --run fts=results/fts.jsonl \
  --run rrf=results/rrf.jsonl \
  --run rerank=results/rerank.jsonl \
  --run faiss=results/faiss.jsonl \
  --ks 10,20 \
  --output results/benchmark.md
```

## Ablation wrapper

```bash
python3 bench/run_ablation.py \
  --qrels evals/qrels.tsv \
  --dense results/dense.jsonl \
  --fts results/fts.jsonl \
  --rrf results/rrf.jsonl \
  --rerank results/rerank.jsonl \
  --faiss results/faiss.jsonl \
  --ks 10,20
```

必须对比：

- `dense`：pgvector-only 检索
- `fts`：PostgreSQL 全文检索
- `rrf`：dense+sparse RRF 融合
- `rerank`：可选外部分数精排变体
- `faiss`：可选 FAISS 加速变体

所有 run 必须使用相同 query、qrels、K 值和 latency 测量窗口。

