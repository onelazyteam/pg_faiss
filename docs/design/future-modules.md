# Module Design: Future Modules

## `src/disk_graph`

Status: scaffold.

Target responsibility:

- Disk-oriented vector graph for larger-than-memory workloads.
- Clear API boundary compatible with current function-style calls.
- Evaluation against FAISS and pgvector using the same offline metrics.

## `src/fts_rerank`

Status: SQL rerank v1 implemented.

Target responsibility:

- Cross-encoder, LLM, and rule-based rerank helpers beyond base candidates.
- Optional weighting, `none` / `minmax` normalization, and rerank diagnostics.
- Compatibility with RRF fusion outputs.
- Model inference does not run inside the PostgreSQL backend; the extension receives externally computed scores.

## Integration Contract

Every retrieval module should be able to export:

- `qid`
- `method`
- ordered result IDs
- query latency in milliseconds

That contract is enough for `evals/run_eval.py` to compare modules uniformly.

Performance test document: [../benchmark/future-modules.md](../benchmark/future-modules.md).
