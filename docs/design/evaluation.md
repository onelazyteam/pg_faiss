# Module Design: Evaluation

## Scope

`evals` owns offline validation for retrieval quality and tail latency. It does
not connect to PostgreSQL directly; SQL and benchmark scripts export run JSONL
files, then `evals/run_eval.py` computes comparable metrics.

## Required Metrics

- `Recall@K`: fraction of relevant qrels recovered in the top K.
- `NDCG@K`: graded relevance ranking quality in the top K.
- `latency_p95_ms`: nearest-rank P95 query latency.
- `latency_p99_ms`: nearest-rank P99 query latency.

Run at least the production K values and one wider diagnostic K. For example:

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## Qrels Format

Tab-separated:

```text
qid<TAB>doc_id<TAB>relevance
```

Relevance values greater than zero are relevant for Recall@K. NDCG@K uses the
graded relevance value.

## Run Format

Preferred query-level JSONL:

```json
{"qid":"q1","method":"rrf","latency_ms":4.2,"results":[{"id":"d1"},{"id":"d2"}]}
```

Row-level JSONL is also accepted:

```json
{"qid":"q1","method":"rrf","doc_id":"d1","rank":1,"latency_ms":4.2}
```

## Acceptance Rule

RRF is considered useful only when the evaluation table shows the tradeoff
explicitly:

- Quality: Recall@K and NDCG@K should be no worse than the chosen baseline within
  the accepted tolerance, or the quality gain must justify latency cost.
- Latency: P95/P99 should remain inside the service budget.
- Ablation: vector-only, FTS-only, and RRF must be reported together.
