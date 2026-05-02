# pg_retrieval_engine

English | [中文](README.zh.md)

`pg_retrieval_engine` is a PostgreSQL hybrid retrieval extension. It combines vector retrieval, full-text retrieval, ranking fusion, evaluation, and observability inside PostgreSQL. The current version uses FAISS as the high-performance ANN execution engine, reuses pgvector's `vector` type, uses PostgreSQL `tsvector` for full-text retrieval, and fuses dense/sparse rankings with RRF.

## 1. Project Scope

### 1.1 What It Does

| Capability | Status | Description |
|---|---|---|
| FAISS in PostgreSQL | implemented | Create, train, add, and search FAISS indexes inside a PostgreSQL backend |
| Vector retrieval API | implemented | Supports `hnsw`, `ivfflat`, `ivfpq`; metrics: `l2`, `ip`, `cosine` |
| Batch search optimization | implemented | Uses `batch_size` chunking to bound memory for large query batches |
| Filtered retrieval | implemented | Filters ANN candidates by a `filter_ids` allow-list |
| Document ingest and chunking | implemented v1 | Registers multi-source extracted text, structured chunks, parent-child chunks, metadata/citation metadata |
| Embedding versions and incremental queue | implemented v1 | Tracks embedding model versions and queues changed chunks by content hash |
| pgvector index management | implemented v1 | Creates `pgvector` HNSW / IVFFlat indexes |
| RRF fusion | implemented | Fuses pgvector rankings with PostgreSQL `tsvector` full-text rankings |
| FAISS + FTS retrieval | implemented v1 | Runs FAISS dense and `tsvector` sparse retrieval before RRF |
| Observability | implemented | Exposes runtime counters, timings, and latest query knobs |
| Autotune | implemented | Updates defaults in `latency`, `balanced`, and `recall` modes |
| Offline evaluation | implemented | Computes Recall@K, NDCG@K, P95/P99 latency |
| Rerank v1 | implemented | Reranks candidates with external cross-encoder, LLM, or rule-based scores and citation metadata |
| Retrieval explain | implemented v1 | Reports stage counts, overlap, and likely failure reason |
| disk graph | planned | Disk-oriented vector graph retrieval for larger datasets |

### 1.2 Repository Layout

```text
contrib/pg_retrieval_engine/
├── README.md / README.zh.md        # Project overview
├── Makefile                        # PGXS build entry
├── pg_retrieval_engine.control     # PostgreSQL extension metadata
├── sql/                            # Extension install/upgrade SQL and SQL templates
├── src/
│   ├── faiss_in_pg/                # FAISS C++ execution engine
│   ├── rrf_sql/                    # RRF SQL fusion module notes
│   ├── disk_graph/                 # Planned disk graph module
│   └── fts_rerank/                 # SQL rerank v1 module notes
├── docs/                           # Architecture, API, usage, benchmark, module design docs
├── evals/                          # Offline metrics scripts, qrels, sample run files
├── bench/                          # Benchmark/ablation script entry points
├── test/                           # Regression and TAP tests
├── demo/                           # Demo scaffold
└── site/                           # GitHub Pages source
```

### 1.3 Modules and Quantitative Metrics

| Module | Area | Required metrics | Current target/result |
|---|---|---|---|
| FAISS in PostgreSQL | ANN vector retrieval | Recall@10, avg latency, P95/P99 latency, speedup vs pgvector | CPU target `>=5x`; measured batch HNSW `11.32x`, IVFFlat `10.31x` on the local sample |
| RRF SQL | Hybrid ranking fusion | Recall@K, NDCG@K, P95/P99 latency, vector/FTS/RRF ablation | vector-only, FTS-only, and RRF runs must be reported together |
| Ingest/chunk/embedding queue | Data preparation | chunk counts, incremental job counts, metadata/citation completeness | external parsers and embedding workers stay outside the extension |
| Observability/autotune | Runtime quality | search calls, avg latency, last_candidate_k, preferred_batch_size, before/after recall and latency | every tuning change must be re-evaluated with fixed qrels |
| Offline evaluation | Acceptance metrics | Recall@K, NDCG@K, latency_p95_ms, latency_p99_ms | supported by `evals/run_eval.py` |
| Rerank v1 | Candidate reranking | Recall@K, NDCG@K, P95/P99 latency, rerank ablation | compare base, cross-encoder, LLM, and rule-based variants |
| disk graph | Future module | same quality and tail-latency metrics as FAISS/RRF | module-specific benchmark docs required before implementation |

## 2. Build and Install

### 2.1 Dependencies

- PostgreSQL 18.3
- pgvector 0.8.2
- FAISS 1.14.1
- C++17 compiler

macOS CPU FAISS example:

```bash
brew install cmake libomp

git clone --branch v1.14.1 https://github.com/facebookresearch/faiss.git
cd faiss
cmake -B build \
  -DFAISS_ENABLE_GPU=OFF \
  -DBUILD_TESTING=OFF \
  -DFAISS_ENABLE_PYTHON=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/faiss-install \
  -DOpenMP_CXX_FLAGS="-Xpreprocessor -fopenmp -I/usr/local/opt/libomp/include" \
  -DOpenMP_CXX_LIB_NAMES=omp \
  -DOpenMP_omp_LIBRARY=/usr/local/opt/libomp/lib/libomp.dylib
cmake --build build -j
cmake --install build
```

### 2.2 Build Extension

```bash
cd contrib/pg_retrieval_engine
make \
  PG_CPPFLAGS="-I$HOME/faiss-install/include -I/usr/local/opt/libomp/include -std=c++17" \
  SHLIB_LINK="-L$HOME/faiss-install/lib -lfaiss -L/usr/local/opt/libomp/lib -lomp -framework Accelerate -lc++ -lc++abi -bundle_loader $(pg_config --bindir)/postgres"
make install
```

GPU build:

```bash
make USE_FAISS_GPU=1 FAISS_GPU_LIBS="-lfaiss -lcudart -lcublas"
make install
```

### 2.3 Enable Extension

```sql
CREATE EXTENSION vector;
CREATE EXTENSION pg_retrieval_engine;
```

## 3. Usage Entry Points

Vector index:

```sql
SELECT pg_retrieval_engine_index_create(
  'docs_hnsw', 768, 'cosine', 'hnsw',
  '{"m":32,"ef_construction":200,"ef_search":64}'::jsonb,
  'cpu'
);
```

RRF fusion:

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
  '{"vector_k":100,"fts_k":100,"rrf_k":60}'::jsonb
);
```

Offline evaluation:

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## 4. Documentation

| Type | English | Chinese |
|---|---|---|
| Architecture | [docs/architecture.md](docs/architecture.md) | [docs/architecture.zh.md](docs/architecture.zh.md) |
| API | [docs/api.md](docs/api.md) | [docs/api.zh.md](docs/api.zh.md) |
| Usage | [docs/usage.md](docs/usage.md) | [docs/usage.zh.md](docs/usage.zh.md) |
| Benchmark | [docs/benchmark.md](docs/benchmark.md) | [docs/benchmark.zh.md](docs/benchmark.zh.md) |
| Module design | [docs/design.md](docs/design.md) | [docs/design.zh.md](docs/design.zh.md) |

## 5. Tests

```bash
make installcheck
prove -I ./test/perl test/t/010_recall.pl
```

Heavy benchmark:

```bash
pg_retrieval_engine_RUN_PERF=1 \
pg_retrieval_engine_PERF_ROWS=1000000 \
pg_retrieval_engine_PERF_DIM=768 \
pg_retrieval_engine_PERF_QUERIES=100 \
prove -I ./test/perl test/t/020_perf_cpu_vs_pgvector.pl
```
