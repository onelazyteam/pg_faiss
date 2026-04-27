# Module Design: Future Modules

## `src/disk_graph`

Status: scaffold.

Target responsibility:

- Disk-oriented vector graph for larger-than-memory workloads.
- Clear API boundary compatible with current function-style calls.
- Evaluation against FAISS and pgvector using the same offline metrics.

## `src/fts_rerank`

Status: scaffold.

Target responsibility:

- Sparse/FTS rerank helpers beyond basic `tsvector` candidate generation.
- Optional feature weighting, normalization, and rerank diagnostics.
- Compatibility with RRF fusion outputs.

## Integration Contract

Every retrieval module should be able to export:

- `qid`
- `method`
- ordered result IDs
- query latency in milliseconds

That contract is enough for `evals/run_eval.py` to compare modules uniformly.

Performance test document: [../benchmark/future-modules.md](../benchmark/future-modules.md).
