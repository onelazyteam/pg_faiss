# pg_faiss v0.2 Design

## 1. Goals

- Provide a function-based FAISS integration for PostgreSQL without implementing a new Index AM.
- Use `vector` / `vector[]` as the primary data path to reduce array conversion overhead.
- Support CPU and optional GPU runtime modes.
- Keep persistence compatible via FAISS binary index files plus a lightweight metadata sidecar.

## 1.1 Baseline and Dependency Versions

- PostgreSQL: 18.3
- pgvector: 0.8.2 (baseline version for this comparison)
- FAISS: 1.14.1 (CPU; GPU optional)

FAISS CPU install contract (full commands in `docs/usage.md`):
- `FAISS_ENABLE_GPU=OFF`
- `CMAKE_BUILD_TYPE=Release`
- recommended install prefix: `$HOME/faiss-install`

## 2. Architecture

### 2.1 Core Components

- Extension entry: `src/pg_faiss.cpp`
- Registry: backend-local hash table keyed by index name (`PgFaissIndexEntry`)
- Runtime index objects:
  - Always maintain a CPU index (`faiss::Index*`)
  - Optionally maintain a GPU clone when `device = 'gpu'` and build enables GPU

### 2.2 Data Flow

1. `pg_faiss_index_create`
- Parse `metric`, `index_type`, `options`, `device`
- Build FAISS index (`HNSW`, `IVFFlat`, or `IVFPQ`)
- Wrap with `IndexIDMap2` to support explicit IDs

2. `pg_faiss_index_train`
- Convert `vector[]` to contiguous float buffer
- Normalize vectors for cosine metric
- Train IVF family indexes

3. `pg_faiss_index_add`
- Convert `ids bigint[]` and `vectors vector[]`
- Add with IDs through `IndexIDMap2`

4. `pg_faiss_index_search` / `pg_faiss_index_search_batch`
- Parse per-query `search_params` (`ef_search`, `nprobe`)
- Apply temporary search settings on index
- Execute FAISS search and return table rows

5. `pg_faiss_index_save` / `pg_faiss_index_load`
- Save FAISS index as binary file (`write_index`)
- Save metadata as `<path>.meta`
- Load binary + metadata and rebuild runtime state

## 3. API Surface

| Function | Description |
|---|---|
| `pg_faiss_index_create` | Create index and runtime settings |
| `pg_faiss_index_train` | Train IVF indexes |
| `pg_faiss_index_add` | Bulk add vectors with explicit IDs |
| `pg_faiss_index_search` | Single-query ANN search |
| `pg_faiss_index_search_batch` | Batch ANN search |
| `pg_faiss_index_save` | Persist index and metadata |
| `pg_faiss_index_load` | Load persisted index |
| `pg_faiss_index_stats` | Return runtime stats as `jsonb` |
| `pg_faiss_index_drop` | Drop one index |
| `pg_faiss_reset` | Drop all backend-local indexes |

## 4. Defaults

- HNSW: `m=32`, `ef_construction=200`, `ef_search=64`
- IVFFlat: `nlist=4096`, `nprobe=32`
- IVFPQ: `nlist=4096`, `pq_m=64`, `pq_bits=8`, `nprobe=32`
- Metrics: `l2`, `ip`, `cosine` (`cosine` uses normalization + IP)

## 5. Testing Strategy

- `pg_regress`: lifecycle and correctness of create/train/add/search/save/load/drop/reset.
- TAP recall: compare with exact baseline, require `Recall@10 >= 0.95`.
- TAP performance:
  - CPU: compare against pgvector HNSW/IVFFlat, require speedup target (default 5x)
  - GPU: conditional run, require speedup target (default 10x)

### 5.1 Performance Methodology

- Acceptance contract: same machine, same dataset, same query set, and same recall constraint (`Recall@10 >= 95%`).
- CPU gate: `>=5x`; GPU gate: `>=10x`.
- Heavy acceptance set: `1M x 768` driven by `test/t/020_perf_cpu_vs_pgvector.pl` and `test/t/030_perf_gpu_vs_pgvector.pl`.
- README lightweight reproducible sample: `contrib/pg_faiss/test/bench/bench_cpu_batch_sample.sql` (`20,000 x 128`).

### 5.2 CPU Snapshot On This Machine (2026-04-14, Batch Query Path)

- Scale: `20,000 x 128`, `29` queries, `k=10`
- Baseline: pgvector 0.8.2
- Parameters: pgvector `hnsw.ef_search=512`, `ivfflat.probes=16`; pg_faiss `ef_search=128`, `nprobe=16`
- Results:
  - HNSW: `11.32x` (pgvector `1.13 ms` vs pg_faiss(batch) `0.10 ms`, `Recall@10 = 0.9552` vs `1.0`)
  - IVFFlat: `10.31x` (pgvector `0.76 ms` vs pg_faiss(batch) `0.07 ms`, both `Recall@10 = 1.0`)

## 6. CI Strategy

- PR/default CI: run correctness + recall only.
- Main/nightly: enable heavy performance tests with env flags:
  - `PG_FAISS_RUN_PERF=1`
  - `PG_FAISS_RUN_PERF_GPU=1`
