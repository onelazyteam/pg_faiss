# Quantitative Test: RRF SQL Fusion

## Goal

Validate whether RRF improves hybrid retrieval quality enough to justify its SQL fusion cost.

## Metrics

- Recall@K
- NDCG@K
- P95 latency
- P99 latency

## Required Ablation

| Run | Description |
|---|---|
| `vector` | pgvector-only dense ranking |
| `fts` | PostgreSQL `tsvector` full-text ranking |
| `rrf` | `pg_retrieval_engine_hybrid_search` fused ranking |

All runs must use the same queries, qrels, K values, and latency measurement window.

## Command

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## Acceptance Rule

RRF is accepted only when one of these is true:

- Recall@K or NDCG@K improves over both single-channel baselines within the latency budget.
- RRF matches the best single-channel quality while materially improving robustness across query types.

P95/P99 latency must remain within the service budget for the target workload.
