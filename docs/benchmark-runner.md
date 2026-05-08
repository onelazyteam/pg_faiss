# Benchmark Runner

Status: implemented in `bench/run_bench.py` and `bench/run_ablation.py`.

The benchmark runner consumes exported JSONL run files and fixed qrels, then reports Recall@K, NDCG@K, and latency P50/P95/P99.

## Standard Report

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

## Ablation Wrapper

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

Required comparison set:

- `dense`: pgvector-only retrieval
- `fts`: PostgreSQL full-text retrieval
- `rrf`: dense+sparse RRF fusion
- `rerank`: optional external-score rerank variant
- `faiss`: optional FAISS accelerator variant

All runs must use the same queries, qrels, K values, and latency measurement window.

