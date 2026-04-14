# pg_faiss v0.2 API Reference

## 1. Notes

- All APIs operate on a backend-local in-memory registry (not shared across PostgreSQL sessions/backends).
- Primary input types are `vector` / `vector[]` from `pgvector`.
- For `metric='cosine'`, pg_faiss normalizes vectors and runs IP internally; returned distance is converted to `1 - inner_product`.
- If `k > ntotal`, the effective top-k is `min(k, ntotal)`.
- For `void`-return functions, SQL evaluates them as non-`NULL` void values; `IS NOT NULL` is the practical success check.

## 2. API Overview

| Function | Purpose | Return |
|---|---|---|
| `pg_faiss_index_create` | Create and register an index object in current backend | `void` |
| `pg_faiss_index_train` | Train IVF/IVFPQ index | `void` |
| `pg_faiss_index_add` | Bulk add vectors with explicit IDs | `bigint` (rows added) |
| `pg_faiss_index_search` | Single-vector ANN search | `table(id bigint, distance real)` |
| `pg_faiss_index_search_batch` | Batch ANN search | `table(query_no int, id bigint, distance real)` |
| `pg_faiss_index_save` | Persist index to disk | `void` |
| `pg_faiss_index_load` | Load index from disk | `void` |
| `pg_faiss_index_stats` | Return runtime stats | `jsonb` |
| `pg_faiss_index_drop` | Drop one index | `void` |
| `pg_faiss_reset` | Drop all pg_faiss indexes in current backend | `void` |

## 3. Detailed API

### 3.1 `pg_faiss_index_create`

Signature:

```sql
pg_faiss_index_create(
  name text,
  dim int,
  metric text,
  index_type text,
  options jsonb default '{}'::jsonb,
  device text default 'cpu'
) returns void
```

Purpose: create and initialize an index object.

Parameters:

| Param | Type | Required | Meaning | Constraints / Default |
|---|---|---|---|---|
| `name` | `text` | Yes | Index name (unique in current backend) | Max 63 chars |
| `dim` | `int` | Yes | Vector dimensionality | `1..65535` |
| `metric` | `text` | Yes | Distance metric | `l2` / `ip` / `inner_product` / `cosine` |
| `index_type` | `text` | Yes | Index type | `hnsw` / `ivfflat` / `ivf_flat` / `ivfpq` / `ivf_pq` |
| `options` | `jsonb` | No | Build-time parameters | See table below |
| `device` | `text` | No | Runtime device | `cpu` (default) / `gpu` |

Supported `options` keys:

| Key | Meaning | Default | Range |
|---|---|---:|---|
| `m` | HNSW connectivity | `32` | `2..256` |
| `ef_construction` | HNSW build search width | `200` | `4..1000000` |
| `ef_search` | Default HNSW search width | `64` | `1..1000000` |
| `nlist` | IVF cluster count | `4096` | `1..1000000` |
| `nprobe` | Default IVF probes | `32` | `1..1000000` |
| `pq_m` | IVFPQ subquantizers | `64` | `1..4096` |
| `pq_bits` | IVFPQ bits per subvector | `8` | `1..16` |
| `gpu_device` | GPU device ordinal | `0` | `0..128` |

Common errors:

- Duplicate index name.
- `device='gpu'` while extension is built without GPU support.
- Out-of-range values or non-integer `options` values.

### 3.2 `pg_faiss_index_train`

Signature:

```sql
pg_faiss_index_train(name text, training_vectors vector[]) returns void
```

Purpose: train IVF/IVFPQ indexes. (HNSW does not require explicit training.)

Parameters:

| Param | Type | Required | Meaning | Constraints |
|---|---|---|---|---|
| `name` | `text` | Yes | Index name | Must exist |
| `training_vectors` | `vector[]` | Yes | Training vectors | 1D, non-empty, no `NULL`, must match `dim` |

### 3.3 `pg_faiss_index_add`

Signature:

```sql
pg_faiss_index_add(name text, ids bigint[], vectors vector[]) returns bigint
```

Purpose: bulk add vectors with explicit IDs.

Parameters:

| Param | Type | Required | Meaning | Constraints |
|---|---|---|---|---|
| `name` | `text` | Yes | Index name | Must exist |
| `ids` | `bigint[]` | Yes | External/business IDs | 1D, non-empty, no `NULL` |
| `vectors` | `vector[]` | Yes | Vector payload | 1D, non-empty, no `NULL`, dims must match |

Return:

- `bigint`: number of vectors added.

Common errors:

- `ids` and `vectors` length mismatch.
- IVF/IVFPQ index not trained yet.

### 3.4 `pg_faiss_index_search`

Signature:

```sql
pg_faiss_index_search(
  name text,
  query vector,
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

Purpose: ANN search for a single query vector.

Parameters:

| Param | Type | Required | Meaning | Constraints / Default |
|---|---|---|---|---|
| `name` | `text` | Yes | Index name | Must exist |
| `query` | `vector` | Yes | Query vector | Must match index dim |
| `k` | `int` | Yes | Top-k | `>0` |
| `search_params` | `jsonb` | No | Per-query runtime params | Supports `ef_search`, `nprobe` |

Supported `search_params` keys:

| Key | Applies to | Meaning | Range |
|---|---|---|---|
| `ef_search` | HNSW | Query-time search width | `1..1000000` |
| `nprobe` | IVF/IVFPQ | Query-time probes | `1..1000000` |

Return columns:

- `id`: vector ID
- `distance`: distance score

### 3.5 `pg_faiss_index_search_batch`

Signature:

```sql
pg_faiss_index_search_batch(
  name text,
  queries vector[],
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

Purpose: ANN search for multiple query vectors in one call (recommended for high throughput).

Parameters:

| Param | Type | Required | Meaning | Constraints |
|---|---|---|---|---|
| `name` | `text` | Yes | Index name | Must exist |
| `queries` | `vector[]` | Yes | Query vector array | 1D, non-empty, no `NULL`, dims must match |
| `k` | `int` | Yes | Top-k per query | `>0` |
| `search_params` | `jsonb` | No | Per-query runtime params | Same as `search` |

Return columns:

- `query_no`: 1-based position in input `queries[]`
- `id`: vector ID
- `distance`: distance score

### 3.6 `pg_faiss_index_save`

Signature:

```sql
pg_faiss_index_save(name text, path text) returns void
```

Purpose: persist index artifacts.

Behavior:

- Writes index file to `path`
- Writes metadata to `path.meta`

Parameters:

| Param | Type | Required | Meaning |
|---|---|---|---|
| `name` | `text` | Yes | Index name |
| `path` | `text` | Yes | Target file path |

### 3.7 `pg_faiss_index_load`

Signature:

```sql
pg_faiss_index_load(name text, path text, device text default 'cpu') returns void
```

Purpose: load index from disk and register it under a new name.

Parameters:

| Param | Type | Required | Meaning | Constraints / Default |
|---|---|---|---|---|
| `name` | `text` | Yes | New index name | Must not exist in current backend |
| `path` | `text` | Yes | Index file path | Must be readable |
| `device` | `text` | No | Runtime device after load | `cpu` (default) / `gpu` |

Notes:

- If `path.meta` exists, metadata is used to recover metric/index settings.
- If no metadata exists, pg_faiss infers index type from FAISS object type.

### 3.8 `pg_faiss_index_stats`

Signature:

```sql
pg_faiss_index_stats(name text) returns jsonb
```

Purpose: return runtime metadata snapshot.

Key fields:

- `name`, `version`, `dim`, `metric`, `index_type`, `device`
- `num_vectors`, `is_trained`
- `hnsw.m`, `hnsw.ef_construction`, `hnsw.ef_search`
- `ivf.nlist`, `ivf.nprobe`
- `ivfpq.m`, `ivfpq.bits`
- `index_path`

### 3.9 `pg_faiss_index_drop`

Signature:

```sql
pg_faiss_index_drop(name text) returns void
```

Purpose: drop one index and free runtime resources.

### 3.10 `pg_faiss_reset`

Signature:

```sql
pg_faiss_reset() returns void
```

Purpose: drop all pg_faiss indexes in current backend.

## 4. Minimal Example

```sql
SELECT pg_faiss_index_create('demo', 4, 'l2', 'hnsw', '{}'::jsonb, 'cpu');
SELECT pg_faiss_index_add('demo', ARRAY[1]::bigint[], ARRAY['[0,1,2,3]'::vector]::vector[]);
SELECT * FROM pg_faiss_index_search('demo', '[0,1,2,3]'::vector, 5, '{}'::jsonb);
SELECT pg_faiss_index_drop('demo');
```
