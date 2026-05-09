# pg_retrieval_engine API Reference (Detailed)

## 1. Global Notes

- pgvector and PostgreSQL tables are the production-consistent source of truth.
- FAISS index objects are backend-local optional accelerators and are not globally shared across sessions.
- Extension-managed documents are tenant-scoped by `(tenant_id, source_uri)`; pass `"tenant_id"` in document metadata and retrieval options.
- ACL data is JSONB (`acl`) and can be enforced through `acl_filter`.
- Input types are provided by `pgvector`: `vector` / `vector[]`.
- `metric='cosine'` is implemented as normalized inner product; returned distance is `1 - ip`.
- Effective return count is always `min(k, ntotal)`.

## 2. Function List

| Function | Return | Purpose |
|---|---|---|
| `pg_retrieval_engine_index_create` | `void` | Create index object |
| `pg_retrieval_engine_index_train` | `void` | Train IVF/IVFPQ |
| `pg_retrieval_engine_index_add` | `bigint` | Bulk insert vectors |
| `pg_retrieval_engine_index_search` | `table(id, distance)` | Single-query ANN |
| `pg_retrieval_engine_index_search_batch` | `table(query_no, id, distance)` | Batch ANN (optimized path) |
| `pg_retrieval_engine_index_search_filtered` | `table(id, distance)` | Hybrid retrieval (single query, ID filter) |
| `pg_retrieval_engine_index_search_batch_filtered` | `table(query_no, id, distance)` | Hybrid retrieval (batch query, ID filter) |
| `pg_retrieval_engine_document_upsert` | `bigint` | Register/update extracted multi-source document text |
| `pg_retrieval_engine_chunk_document` | `table(...)` | Structured chunks, parent-child chunks, metadata/citation metadata |
| `pg_retrieval_engine_embedding_version_create` | `bigint` | Create/update an embedding version |
| `pg_retrieval_engine_enqueue_embedding_jobs` | `integer` | Queue changed chunks by content hash |
| `pg_retrieval_engine_claim_embedding_jobs` | `table(...)` | Atomically lease pending, failed, or timed-out embedding jobs for external workers |
| `pg_retrieval_engine_embedding_job_complete` | `void` | Persist embeddings produced by an external worker |
| `pg_retrieval_engine_embedding_job_fail` | `void` | Mark an embedding job failed and clear its lease for retry |
| `pg_retrieval_engine_activate_embedding_version` | `integer` | Promote versioned chunk embeddings into the latest chunk vector column |
| `pg_retrieval_engine_pgvector_index_create` | `text` | Create pgvector HNSW / IVFFlat indexes |
| `pg_retrieval_engine_tsvector_index_create` | `text` | Create `tsvector` GIN indexes |
| `pg_retrieval_engine_rrf_fuse` | `table(id, rrf_score, vector_rank, fts_rank)` | Fuse two ranked ID lists |
| `pg_retrieval_engine_hybrid_search` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | pgvector + `tsvector` RRF hybrid search |
| `pg_retrieval_engine_hybrid_search_batch` | `table(query_no, ...)` | Batch wrapper for pgvector + `tsvector` RRF hybrid search |
| `pg_retrieval_engine_search_chunks` | `table(chunk_id, content, context_content, citation_metadata, ...)` | Agent-ready search over extension-managed chunks |
| `pg_retrieval_engine_hybrid_search_faiss` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | FAISS + `tsvector` RRF hybrid search |
| `pg_retrieval_engine_rerank` | `table(id, final_score, base_rank, base_score, cross_encoder_score, llm_score, rule_score, diagnostics)` | Rerank candidates with external model/rule scores |
| `pg_retrieval_engine_rerank_with_citations` | `table(..., citation, diagnostics)` | Rerank candidates with citation metadata |
| `pg_retrieval_engine_retrieval_explain` | `jsonb` | Report stage counts, filters, fusion diagnostics, and likely failure reason |
| `pg_retrieval_engine_hybrid_autotune` | `jsonb` | Recommend hybrid search knobs for latency/balanced/recall modes |
| `pg_retrieval_engine_index_autotune` | `jsonb` | Auto tune FAISS runtime defaults |
| `pg_retrieval_engine_metrics_reset` | `void` | Reset runtime counters |
| `pg_retrieval_engine_index_save` | `void` | Persist index |
| `pg_retrieval_engine_index_load` | `void` | Load index |
| `pg_retrieval_engine_index_stats` | `jsonb` | Metadata + runtime metrics |
| `pg_retrieval_engine_index_drop` | `void` | Drop index |
| `pg_retrieval_engine_reset` | `void` | Drop all indexes in current backend |

## 3. API Details

### 3.1 `pg_retrieval_engine_index_create`

```sql
pg_retrieval_engine_index_create(
  name text,
  dim int,
  metric text,
  index_type text,
  options jsonb default '{}'::jsonb,
  device text default 'cpu'
) returns void
```

Arguments:

- `name`: backend-local unique name, max 63 chars.
- `dim`: vector dimension, range `1..65535`.
- `metric`: `l2` / `ip` / `inner_product` / `cosine`.
- `index_type`: `hnsw` / `ivfflat` / `ivf_flat` / `ivfpq` / `ivf_pq`.
- `options`: index build options.
- `device`: `cpu` (default) / `gpu`.

Supported `options`:

- `m` (HNSW, default 32)
- `ef_construction` (HNSW, default 200)
- `ef_search` (HNSW, default 64)
- `nlist` (IVF, default 4096)
- `nprobe` (IVF, default 32)
- `pq_m` (IVFPQ, default 64)
- `pq_bits` (IVFPQ, default 8)
- `gpu_device` (GPU id, default 0)

### 3.2 `pg_retrieval_engine_index_train`

```sql
pg_retrieval_engine_index_train(name text, training_vectors vector[]) returns void
```

- `training_vectors` must be one-dimensional, non-empty, no NULLs, and dimension-matched.

### 3.3 `pg_retrieval_engine_index_add`

```sql
pg_retrieval_engine_index_add(name text, ids bigint[], vectors vector[]) returns bigint
```

- `ids` and `vectors` must have identical length.
- Returns number of vectors inserted.

### 3.4 `pg_retrieval_engine_index_search`

```sql
pg_retrieval_engine_index_search(
  name text,
  query vector,
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

`search_params`:

- `ef_search` (HNSW query breadth)
- `nprobe` (IVF probes)
- `candidate_k` (candidate depth, default `k`)

### 3.5 `pg_retrieval_engine_index_search_batch`

```sql
pg_retrieval_engine_index_search_batch(
  name text,
  queries vector[],
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

`search_params`:

- `ef_search`
- `nprobe`
- `candidate_k`
- `batch_size` (chunk size, default = index `preferred_batch_size`)

### 3.6 `pg_retrieval_engine_index_search_filtered`

```sql
pg_retrieval_engine_index_search_filtered(
  name text,
  query vector,
  k int,
  filter_ids bigint[],
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

Performs ANN retrieval and keeps only IDs from `filter_ids`.

### 3.7 `pg_retrieval_engine_index_search_batch_filtered`

```sql
pg_retrieval_engine_index_search_batch_filtered(
  name text,
  queries vector[],
  k int,
  filter_ids bigint[],
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

Batch hybrid retrieval with per-query top-k after filtering.

### 3.8 Ingest, Chunking, and Embedding Queue

```sql
pg_retrieval_engine_document_upsert(source_uri text, source_type text, content text, metadata jsonb default '{}'::jsonb, title text default null) returns bigint
pg_retrieval_engine_chunk_document(document_id bigint, chunk_size int default 1000, chunk_overlap int default 100, options jsonb default '{}'::jsonb) returns table(...)
pg_retrieval_engine_embedding_version_create(model_name text, model_version text, dimensions int, distance_metric text default 'cosine', metadata jsonb default '{}'::jsonb, is_active boolean default true) returns bigint
pg_retrieval_engine_enqueue_embedding_jobs(embedding_version_id bigint, only_changed boolean default true) returns integer
pg_retrieval_engine_claim_embedding_jobs(embedding_version_id bigint, batch_size int default 100, worker_id text default null, lease_timeout_seconds int default 900, max_attempts int default 5) returns table(...)
pg_retrieval_engine_embedding_job_complete(job_id bigint, embedding vector, metadata jsonb default '{}'::jsonb, expected_attempt int default null, worker_id text default null) returns void
pg_retrieval_engine_embedding_job_fail(job_id bigint, error_message text, metadata jsonb default '{}'::jsonb, expected_attempt int default null, worker_id text default null) returns void
pg_retrieval_engine_activate_embedding_version(embedding_version_id bigint, tenant_id text default null) returns integer
```

The extension stores tenant-scoped extracted text, stable structured chunks, parent-child links, metadata, ACL JSONB, citation metadata, embedding versions, versioned chunk embeddings, and incremental embedding jobs. Binary PDF/HTML parsing and embedding model execution stay outside PostgreSQL.

`pg_retrieval_engine_document_upsert` reads optional `metadata.tenant_id` and `metadata.acl`. The uniqueness key is `(tenant_id, source_uri)`. Tenant IDs are constrained to `^[A-Za-z0-9_.:-]{1,128}$` to keep tenant filters predictable across SQL and worker paths.

`pg_retrieval_engine_chunk_document` upserts chunks by `(document_id, chunk_type, chunk_no)` instead of deleting and reinserting all rows. Reused positions keep their chunk IDs. If chunk content changes, the latest `embedding` on `pg_retrieval_engine_chunks` is cleared so workers can re-embed safely.

`pg_retrieval_engine_claim_embedding_jobs` uses `FOR UPDATE SKIP LOCKED` to lease pending, failed, or timed-out running jobs and increments `attempts`. It returns the current chunk content hash, refreshing stale job hashes at claim time when a chunk has changed. `lease_timeout_seconds` controls stale running job takeover and `max_attempts` prevents endless retry loops.

`pg_retrieval_engine_embedding_job_complete` requires a claimed `running` job, validates optional `expected_attempt`/`worker_id` fencing, stale content hashes, and `vector_dims(embedding)` against the embedding version, then updates the latest chunk vector and upserts `pg_retrieval_engine_chunk_embeddings`.

`pg_retrieval_engine_embedding_job_fail` records retry diagnostics, supports the same optional fencing, and clears the job lease. `pg_retrieval_engine_activate_embedding_version` promotes current versioned embeddings for one version, optionally scoped to one tenant, into `pg_retrieval_engine_chunks.embedding` for the production search path.

```sql
pg_retrieval_engine_pgvector_index_create(table_name regclass, vector_column name, index_type text, opclass text default 'vector_cosine_ops', options jsonb default '{}'::jsonb) returns text
pg_retrieval_engine_tsvector_index_create(table_name regclass, tsvector_column name) returns text
```

Creates pgvector HNSW / IVFFlat indexes and `tsvector` GIN indexes.

### 3.9 `pg_retrieval_engine_rrf_fuse`

```sql
pg_retrieval_engine_rrf_fuse(
  vector_ids bigint[],
  fts_ids bigint[],
  k int,
  rrf_k double precision default 60.0,
  vector_weight double precision default 1.0,
  fts_weight double precision default 1.0
) returns table(id bigint, rrf_score double precision, vector_rank int, fts_rank int)
```

Fuses two relevance-ordered ID lists with Reciprocal Rank Fusion. Ranks are 1-based; missing ranks contribute 0.

```text
score = vector_weight / (rrf_k + vector_rank)
      + fts_weight    / (rrf_k + fts_rank)
```

### 3.10 `pg_retrieval_engine_hybrid_search`

```sql
pg_retrieval_engine_hybrid_search(
  table_name regclass,
  id_column name,
  vector_column name,
  tsvector_column name,
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(
  id bigint,
  rrf_score double precision,
  vector_rank int,
  fts_rank int,
  vector_distance real,
  fts_score real
)
```

Runs pgvector distance ranking and PostgreSQL `tsvector` full-text ranking on one table, then returns unified top-k results with RRF.

Supported `options`:

- `vector_k` / `dense_k`: vector candidate depth, default `k * 4`
- `fts_k` / `sparse_k`: full-text candidate depth, default `k * 4`
- `rrf_k`: RRF smoothing constant, default `60`
- `vector_weight` / `dense_weight`: vector result weight, default `1`
- `fts_weight` / `sparse_weight`: full-text result weight, default `1`
- `vector_operator`: `<=>` (default, cosine distance) / `<->` (L2) / `<#>` (negative inner product)
- `rank_function`: `ts_rank_cd` (default) / `ts_rank`
- `normalization`: full-text rank normalization, default `32`
- `tenant_id`: equality filter against a `tenant_id` column
- `namespace`: JSONB metadata namespace equality, intended for Agent/RAG collections
- `agent_id`: allow only rows whose ACL `agents` list is absent or contains this agent
- `user_id`: allow only rows whose ACL `users` list is absent or contains this user
- `user_roles` / `allowed_roles`: allow only rows whose ACL `roles` list is absent or overlaps these roles
- `sensitivity_max`: maximum allowed sensitivity, one of `public`, `internal`, `confidential`, `restricted`
- `filters`: scalar column equality filters, for example `{"tenant_id":"acme"}`
- `filters` also accepts simple operator objects:
  `{"status":{"op":"in","value":["active","draft"]}}`,
  `{"deleted_at":{"op":"is_null","value":true}}`,
  `{"properties":{"op":"contains","value":{"doc_type":"manual"}}}`
- operator objects must include `value` for `eq`, `ne`, `in`, and `contains`; use `is_null` for null checks
- `metadata_column`: JSONB metadata column name, default `metadata`
- `metadata_filter`: JSONB metadata filter. Plain values use containment semantics, e.g. `{"doc_type":"manual"}`. Field-level operator objects are also supported:
  `{"doc_type":{"op":"in","value":["manual","runbook"]}}`,
  `{"freshness":{"op":"ne","value":"stale"}}`,
  `{"tags":{"op":"contains","value":["postgres"]}}`,
  `{"deprecated":{"op":"is_null","value":true}}`
- `acl_column`: JSONB ACL column name, default `acl`
- `acl_filter`: JSONB containment filter applied as `acl_column @> acl_filter`
- `soft_delete_column`: nullable timestamp/marker column that must be `NULL`

Permission-aware Agent retrieval should pass the top-level permission fields instead of relying only on similarity. For example:

```json
{
  "tenant_id": "acme",
  "agent_id": "dba-copilot",
  "user_id": "alice",
  "user_roles": ["dba"],
  "namespace": "postgres_runbook",
  "sensitivity_max": "internal"
}
```

### 3.10.1 `pg_retrieval_engine_hybrid_search_batch`

```sql
pg_retrieval_engine_hybrid_search_batch(
  table_name regclass,
  id_column name,
  vector_column name,
  tsvector_column name,
  query_vectors vector[],
  query_tsqueries tsquery[],
  k int,
  options jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, rrf_score double precision, vector_rank int, fts_rank int, vector_distance real, fts_score real)
```

Runs the same hybrid retrieval contract for multiple query vectors and tsqueries. The current implementation is a SQL wrapper around `pg_retrieval_engine_hybrid_search`; it is intended for API ergonomics and evaluation exports, not yet a shared executor-level optimization.

### 3.10.2 `pg_retrieval_engine_search_chunks`

```sql
pg_retrieval_engine_search_chunks(
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(
  chunk_id bigint,
  document_id bigint,
  parent_chunk_id bigint,
  chunk_type text,
  content text,
  context_content text,
  metadata jsonb,
  citation_metadata jsonb,
  rrf_score double precision,
  vector_rank int,
  fts_rank int,
  vector_distance real,
  fts_score real
)
```

Searches `pg_retrieval_engine_chunks`, forces `chunk_type='child'`, and returns content, optional parent context, metadata, citations, and ranking diagnostics. Supported extra option:

- `return_parent`: when `true`, `context_content` is the parent chunk content when available; otherwise it is the child content.

### 3.11 `pg_retrieval_engine_hybrid_search_faiss`

```sql
pg_retrieval_engine_hybrid_search_faiss(
  table_name regclass,
  id_column name,
  tsvector_column name,
  faiss_index_name text,
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(id bigint, rrf_score double precision, vector_rank int, fts_rank int, vector_distance real, fts_score real)
```

Runs FAISS dense retrieval and PostgreSQL `tsvector` sparse retrieval, joins FAISS candidate IDs back to the target table for row recheck and filters, then fuses both paths with RRF inside PostgreSQL.

It supports the same filter options as `pg_retrieval_engine_hybrid_search`. Additional option:

- `faiss_distance_order`: `asc` (default) or `desc`; use `desc` when a FAISS path returns larger-is-better scores such as raw inner product.

### 3.12 `pg_retrieval_engine_rerank`

```sql
pg_retrieval_engine_rerank(
  candidate_ids bigint[],
  k int,
  cross_encoder_scores double precision[] default null,
  llm_scores double precision[] default null,
  rule_scores double precision[] default null,
  base_scores double precision[] default null,
  options jsonb default '{}'::jsonb
) returns table(
  id bigint,
  final_score double precision,
  base_rank int,
  base_score double precision,
  cross_encoder_score double precision,
  llm_score double precision,
  rule_score double precision,
  diagnostics jsonb
)
```

Reranks an existing candidate list. Cross-encoder and LLM inference is done outside PostgreSQL; this function receives their scores and performs deterministic weighted sorting.

Default formula:

```text
final_score =
  base_weight * base_component +
  cross_encoder_weight * cross_encoder_score +
  llm_weight * llm_score +
  rule_weight * rule_score
```

If `base_scores` is omitted, `base_component` is `1 / (rank_k + base_rank)`. Duplicate candidate IDs keep the first occurrence and matching scores.

Supported `options`:

- `base_weight`: base rank/base score weight, default `1`
- `cross_encoder_weight`: cross-encoder score weight, default `1`
- `llm_weight`: LLM score weight, default `1`
- `rule_weight`: rule-based score weight, default `1`
- `rank_k`: base rank prior smoothing constant, default `60`
- `score_normalization`: `none` (default) / `minmax`

`pg_retrieval_engine_rerank_with_citations(...)` accepts the same scoring arguments plus `citation_metadata jsonb[]`, then attaches citation metadata aligned with the input candidate order.

### 3.13 `pg_retrieval_engine_retrieval_explain`

```sql
pg_retrieval_engine_retrieval_explain(
  vector_ids bigint[] default ARRAY[]::bigint[],
  fts_ids bigint[] default ARRAY[]::bigint[],
  final_ids bigint[] default ARRAY[]::bigint[],
  relevant_ids bigint[] default null,
  options jsonb default '{}'::jsonb
) returns jsonb
```

Returns stage counts, candidate overlap, filter diagnostics, optional latency hints, recalled/missing relevant IDs, and `likely_failure_reason`.

For Agent debugging this output is the retrieval trace source. A trace page can show the user query, retrieval options, dense top K, sparse top K, RRF overlap, rerank result, filtered-out documents when exported by the caller, final context, and likely failure reason.

### 3.14 `pg_retrieval_engine_hybrid_autotune`

```sql
pg_retrieval_engine_hybrid_autotune(
  mode text default 'balanced',
  k int default 10,
  options jsonb default '{}'::jsonb
) returns jsonb
```

Returns heuristic recommendations for `vector_k`, `fts_k`, `rrf_k`, optional `rerank_k`, and pgvector runtime knobs. Treat the output as a starting point and validate it with fixed qrels and P95/P99 latency measurements.

Supported `mode`: `latency` / `balanced` / `recall`.

Supported `options`:

- `target_recall`, default `0.90`
- `target_p95_ms`, optional
- `max_candidate_k`, default `1000`
- `vector_weight`, `fts_weight`

### 3.15 `pg_retrieval_engine_index_autotune`

```sql
pg_retrieval_engine_index_autotune(
  name text,
  mode text default 'balanced',
  options jsonb default '{}'::jsonb
) returns jsonb
```

Arguments:

- `mode`: `latency` / `balanced` / `recall`
- `options`:
  - `target_recall` (default `0.95`)
  - `min_batch_size` (default `32`)
  - `max_batch_size` (default `4096`)

Returns JSON old/new diffs for `hnsw_ef_search`, `ivf_nprobe`, and `preferred_batch_size`.

### 3.16 `pg_retrieval_engine_metrics_reset`

```sql
pg_retrieval_engine_metrics_reset(name text default null) returns void
```

- `name is null`: reset runtime counters for all indexes in current backend.
- `name is not null`: reset only the target index.

### 3.17 `pg_retrieval_engine_index_save`

```sql
pg_retrieval_engine_index_save(name text, path text) returns void
```

- Main index file: `path`
- Sidecar metadata: `path.meta`

### 3.18 `pg_retrieval_engine_index_load`

```sql
pg_retrieval_engine_index_load(name text, path text, device text default 'cpu') returns void
```

Loads a persisted index under a new runtime name.

### 3.19 `pg_retrieval_engine_index_stats`

```sql
pg_retrieval_engine_index_stats(name text) returns jsonb
```

Returns:

- Metadata: `name/version/dim/metric/index_type/device`
- Config snapshots: `hnsw/ivf/ivfpq`
- Runtime metrics: `runtime.*` (call counts, timing totals/averages, latest candidate/batch knobs, autotune state)

### 3.20 `pg_retrieval_engine_index_drop`

```sql
pg_retrieval_engine_index_drop(name text) returns void
```

### 3.21 `pg_retrieval_engine_reset`

```sql
pg_retrieval_engine_reset() returns void
```

### RRF fusion

```sql
SELECT *
FROM pg_retrieval_engine_hybrid_search(
  'documents'::regclass,
  'id',
  'embedding',
  'search_vector',
  '[0.1,0.2,0.3,0.4]'::vector,
  plainto_tsquery('simple', 'vector database'),
  20,
  '{"vector_k":100,"fts_k":100,"rrf_k":60,"vector_operator":"<=>"}'::jsonb
);
```

## 4. Common Errors

- invalid arguments/ranges: `ERRCODE_INVALID_PARAMETER_VALUE`
- missing index: `ERRCODE_UNDEFINED_OBJECT`
- invalid runtime state (for example IVF untrained): `ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE`
- FAISS runtime failures: `ERRCODE_EXTERNAL_ROUTINE_EXCEPTION`

## 5. Hybrid Retrieval Example (Production Pattern)

```sql
WITH allow_list AS (
  SELECT array_agg(id ORDER BY id) AS ids
  FROM product_embedding
  WHERE tenant_id = 42
    AND category = 'electronics'
    AND is_active = true
)
SELECT *
FROM pg_retrieval_engine_index_search_filtered(
  'prod_idx',
  '[0.1,0.2,0.3,0.4]'::vector,
  20,
  (SELECT ids FROM allow_list),
  '{"candidate_k":200,"ef_search":128}'::jsonb
);
```
