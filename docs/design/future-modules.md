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

## Ingest, Chunking, and Embedding Queue

Status: SQL v2 implemented.

Implemented responsibility:

- Tenant-scoped documents keyed by `(tenant_id, source_uri)`.
- Stable chunk upsert keyed by `(document_id, chunk_type, chunk_no)`.
- JSONB ACL propagation from documents to chunks.
- Claimable embedding jobs using `FOR UPDATE SKIP LOCKED`, lease timeout, max attempts, attempt/worker fencing, failure diagnostics, stale claim hash refresh, and stale content-hash rejection.
- Versioned chunk embeddings keyed by `(chunk_id, embedding_version_id)`.
- Explicit activation of a validated embedding version into the latest chunk vector column.

## Integration Contract

Every retrieval module should be able to export:

- `qid`
- `method`
- ordered result IDs
- query latency in milliseconds

That contract is enough for `evals/run_eval.py` to compare modules uniformly.

Performance test document: [../benchmark/future-modules.md](../benchmark/future-modules.md).
