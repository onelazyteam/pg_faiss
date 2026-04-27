# Observability

Current observability is primarily provided by FAISS-in-PG runtime stats.

## APIs

- `pg_retrieval_engine_index_stats(name)`
- `pg_retrieval_engine_metrics_reset(name default null)`

## Metrics

- Calls: `train_calls`, `add_calls`, `search_single_calls`, `search_batch_calls`, `search_filtered_calls`
- Volume: `add_vectors_total`, `search_query_total`, `search_result_total`
- Time: `search_single_ms_total`, `search_batch_ms_total`, `search_filtered_ms_total`
- Operations: `save_calls`, `load_calls`, `autotune_calls`, `error_calls`
- Latest knobs: `last_candidate_k`, `last_batch_size`, `preferred_batch_size`, `last_autotune_mode`

## Validation

Observability counters are used for operations and debugging. Accepting a tuning
change still requires fixed-qrels validation with Recall@K, NDCG@K, P95 latency,
and P99 latency.
