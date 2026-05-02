# pg_retrieval_engine 使用文档

## 1. 前置依赖与安装

### 1.1 安装 pgvector

```bash
cd contrib/pgvector
make
make install
```

### 1.2 安装 FAISS CPU（v1.14.1）

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

### 1.3 构建 pg_retrieval_engine（CPU）

```bash
cd contrib/pg_retrieval_engine
make \
  PG_CPPFLAGS="-I$HOME/faiss-install/include -I/usr/local/opt/libomp/include -std=c++17" \
  SHLIB_LINK="-L$HOME/faiss-install/lib -lfaiss -L/usr/local/opt/libomp/lib -lomp -framework Accelerate -lc++ -lc++abi -bundle_loader $(pg_config --bindir)/postgres"
make install
```

### 1.4 GPU 构建（可选）

```bash
cd contrib/pg_retrieval_engine
make USE_FAISS_GPU=1 FAISS_GPU_LIBS="-lfaiss -lcudart -lcublas"
make install
```

## 2. 启用扩展

```sql
CREATE EXTENSION vector;
CREATE EXTENSION pg_retrieval_engine;
```

## 3. 快速开始

### 3.1 文档导入、Chunk 与增量向量化队列

```sql
SELECT pg_retrieval_engine_document_upsert(
  'file:///docs/retrieval.md',
  'markdown',
  '...',
  '{"repo":"demo","path":"docs/retrieval.md"}'::jsonb,
  'Retrieval Doc'
);

SELECT *
FROM pg_retrieval_engine_chunk_document(
  1,
  1000,
  100,
  '{"parent_chunk_size":3000}'::jsonb
);

SELECT pg_retrieval_engine_embedding_version_create('bge-m3', '2026-05', 1024);
SELECT pg_retrieval_engine_enqueue_embedding_jobs(1);
```

PDF/HTML/Markdown 解析和 embedding 推理由外部 worker 完成；扩展负责存储抽取文本、chunk、metadata、citation metadata 和增量任务状态。

### 3.2 创建与写入

```sql
SELECT pg_retrieval_engine_index_create(
  'docs_hnsw', 768, 'cosine', 'hnsw',
  '{"m":32,"ef_construction":200,"ef_search":64}'::jsonb,
  'cpu'
);

SELECT pg_retrieval_engine_index_add(
  'docs_hnsw',
  ARRAY[1,2,3]::bigint[],
  ARRAY[
    '[0.1,0.2,0.3]'::vector,
    '[0.3,0.2,0.1]'::vector,
    '[0.0,0.5,0.5]'::vector
  ]::vector[]
);
```

### 3.3 单查询

```sql
SELECT *
FROM pg_retrieval_engine_index_search(
  'docs_hnsw',
  '[0.1,0.2,0.3]'::vector,
  10,
  '{"ef_search":128}'::jsonb
);
```

### 3.4 批查询（优化路径）

```sql
SELECT *
FROM pg_retrieval_engine_index_search_batch(
  'docs_hnsw',
  ARRAY['[0.1,0.2,0.3]'::vector, '[0.0,0.5,0.5]'::vector]::vector[],
  5,
  '{"batch_size":256}'::jsonb
);
```

## 4. 新能力使用示例

### 4.1 可观测性

```sql
SELECT pg_retrieval_engine_index_stats('docs_hnsw');
SELECT pg_retrieval_engine_metrics_reset('docs_hnsw');
```

### 4.2 混合检索（ANN + 业务过滤）

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
  'docs_hnsw',
  '[0.1,0.2,0.3]'::vector,
  20,
  (SELECT ids FROM allow_list),
  '{"candidate_k":200,"ef_search":128}'::jsonb
);
```

### 4.3 自动调参

```sql
SELECT pg_retrieval_engine_index_autotune(
  'docs_hnsw',
  'balanced',
  '{"target_recall":0.97,"min_batch_size":64,"max_batch_size":2048}'::jsonb
);
```

### 4.4 批量混合检索

```sql
SELECT *
FROM pg_retrieval_engine_index_search_batch_filtered(
  'docs_hnsw',
  ARRAY['[0.1,0.2,0.3]'::vector, '[0.0,0.5,0.5]'::vector]::vector[],
  10,
  ARRAY[1,2,3,4,5]::bigint[],
  '{"candidate_k":100,"batch_size":128}'::jsonb
);
```

### 4.5 RRF 融合检索（pgvector + tsvector）

业务表需要同时具备向量列和 `tsvector` 列：

```sql
SELECT *
FROM pg_retrieval_engine_hybrid_search(
  'documents'::regclass,
  'id',
  'embedding',
  'search_vector',
  '[0.1,0.2,0.3]'::vector,
  plainto_tsquery('simple', 'vector database'),
  20,
  '{"vector_k":100,"fts_k":100,"rrf_k":60,"vector_operator":"<=>"}'::jsonb
);
```

### 4.6 候选精排

Cross-encoder 分数由应用或外部模型服务计算，再传回 PostgreSQL 做确定性精排：

```sql
SELECT id, final_score, base_rank, cross_encoder_score
FROM pg_retrieval_engine_rerank(
  ARRAY[101,102,103]::bigint[],
  3,
  ARRAY[0.20,0.95,0.40]::double precision[],
  NULL,
  NULL,
  NULL,
  '{"base_weight":0,"cross_encoder_weight":1}'::jsonb
);
```

LLM rerank 分数使用同一接口：

```sql
SELECT id, final_score, llm_score
FROM pg_retrieval_engine_rerank(
  ARRAY[101,102,103]::bigint[],
  2,
  NULL,
  ARRAY[0.70,0.20,0.90]::double precision[],
  NULL,
  NULL,
  '{"base_weight":0,"llm_weight":1}'::jsonb
);
```

Rule-based rerank 可以由 SQL 规则特征生成 `rule_scores` 后传入：

```sql
SELECT id, final_score, rule_score
FROM pg_retrieval_engine_rerank(
  ARRAY[101,102,103]::bigint[],
  3,
  NULL,
  NULL,
  ARRAY[1.0,0.0,0.5]::double precision[],
  NULL,
  '{"base_weight":0.2,"rule_weight":1,"score_normalization":"minmax"}'::jsonb
);
```

### 4.7 离线评测

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

输出包含 Recall@K、NDCG@K、P95 latency、P99 latency。

## 5. 持久化

```sql
SELECT pg_retrieval_engine_index_save('docs_hnsw', '/tmp/docs_hnsw.faiss');
SELECT pg_retrieval_engine_index_drop('docs_hnsw');
SELECT pg_retrieval_engine_index_load('docs_hnsw', '/tmp/docs_hnsw.faiss', 'cpu');
```

## 6. 测试

```bash
make installcheck
prove -I ./test/perl test/t/010_recall.pl
```

重性能测试：

```bash
pg_retrieval_engine_RUN_PERF=1 \
pg_retrieval_engine_PERF_ROWS=1000000 \
pg_retrieval_engine_PERF_DIM=768 \
pg_retrieval_engine_PERF_QUERIES=100 \
prove -I ./test/perl test/t/020_perf_cpu_vs_pgvector.pl
```

## 7. 推荐阅读

- 架构文档：`docs/architecture.zh.md`
- API 细节：`docs/api.zh.md`
- Benchmark：`docs/benchmark.zh.md`
- 设计文档：`docs/design.zh.md`
- 英文文档：`README.md`
