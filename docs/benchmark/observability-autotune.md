# Quantitative Test: Observability and Autotune

## Goal

Verify that runtime counters are accurate enough for operations and that autotune changes improve latency/recall tradeoffs without hidden regressions.

## Metrics

- `search_single_calls`
- `search_batch_calls`
- `search_filtered_calls`
- `search_query_total`
- `search_result_total`
- average latency by search path
- Recall@K before and after autotune
- P95/P99 latency before and after autotune

## Required Comparison

| Run | Description |
|---|---|
| `before_autotune` | default or current production parameters |
| `latency` | after `pg_retrieval_engine_index_autotune(..., 'latency', ...)` |
| `balanced` | after `pg_retrieval_engine_index_autotune(..., 'balanced', ...)` |
| `recall` | after `pg_retrieval_engine_index_autotune(..., 'recall', ...)` |

## Acceptance Rule

Autotune changes must not be accepted from latency counters alone. They require fixed-qrels validation with Recall@K, NDCG@K, P95 latency, and P99 latency.
