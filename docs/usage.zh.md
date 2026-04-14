# pg_faiss v0.2 使用文档

## 1. 前置依赖与 FAISS 安装

### 1.1 PostgreSQL 与 pgvector

```bash
cd contrib/pgvector
make
make install
```

### 1.2 FAISS CPU 安装（v1.14.1）

```bash
# macOS 依赖
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

### 1.3 构建 pg_faiss（CPU）

```bash
cd contrib/pg_faiss
make \
  PG_CPPFLAGS="-I$HOME/faiss-install/include -I/usr/local/opt/libomp/include -std=c++17" \
  SHLIB_LINK="-L$HOME/faiss-install/lib -lfaiss -L/usr/local/opt/libomp/lib -lomp -framework Accelerate -lc++ -lc++abi -bundle_loader $(pg_config --bindir)/postgres"
make install
```

### 1.4 GPU 构建（可选）

```bash
cd contrib/pg_faiss
make USE_FAISS_GPU=1 FAISS_GPU_LIBS="-lfaiss -lcudart -lcublas"
make install
```

## 2. 启用扩展

```sql
CREATE EXTENSION vector;
CREATE EXTENSION pg_faiss;
```

## 3. API 示例

完整 API 参数说明请见：[api.zh.md](api.zh.md)。

### 3.1 创建索引

```sql
SELECT pg_faiss_index_create(
  'docs_hnsw',
  768,
  'cosine',
  'hnsw',
  '{"m":32,"ef_construction":200,"ef_search":64}'::jsonb,
  'cpu'
);
```

### 3.2 批量写入向量

```sql
SELECT pg_faiss_index_add(
  'docs_hnsw',
  ARRAY[1,2,3]::bigint[],
  ARRAY[
    '[0.1,0.2,0.3]'::vector,
    '[0.3,0.2,0.1]'::vector,
    '[0.0,0.5,0.5]'::vector
  ]::vector[]
);
```

### 3.3 单查询检索

```sql
SELECT *
FROM pg_faiss_index_search(
  'docs_hnsw',
  '[0.1,0.2,0.3]'::vector,
  10,
  '{"ef_search":128}'::jsonb
);
```

### 3.4 批查询检索

```sql
SELECT *
FROM pg_faiss_index_search_batch(
  'docs_hnsw',
  ARRAY['[0.1,0.2,0.3]'::vector, '[0.0,0.5,0.5]'::vector]::vector[],
  5,
  '{}'::jsonb
);
```

### 3.5 IVF 训练与检索

```sql
SELECT pg_faiss_index_create(
  'docs_ivf',
  768,
  'l2',
  'ivfflat',
  '{"nlist":4096,"nprobe":32}'::jsonb,
  'cpu'
);

SELECT pg_faiss_index_train('docs_ivf', $training_vectors::vector[]);
SELECT pg_faiss_index_add('docs_ivf', $ids::bigint[], $vectors::vector[]);

SELECT *
FROM pg_faiss_index_search('docs_ivf', $query::vector, 10, '{"nprobe":32}'::jsonb);
```

### 3.6 保存与加载

```sql
SELECT pg_faiss_index_save('docs_hnsw', '/tmp/docs_hnsw.faiss');
SELECT pg_faiss_index_drop('docs_hnsw');
SELECT pg_faiss_index_load('docs_hnsw', '/tmp/docs_hnsw.faiss', 'cpu');
```

### 3.7 统计信息

```sql
SELECT pg_faiss_index_stats('docs_hnsw');
```

## 4. 性能与召回测试

### 4.1 pg_regress

```bash
make installcheck
```

### 4.2 Recall TAP

```bash
prove -I ./test/perl test/t/010_recall.pl
```

### 4.3 CPU 性能 TAP（重负载）

```bash
PG_FAISS_RUN_PERF=1 \
PG_FAISS_PERF_ROWS=1000000 \
PG_FAISS_PERF_DIM=768 \
PG_FAISS_PERF_QUERIES=100 \
prove -I ./test/perl test/t/020_perf_cpu_vs_pgvector.pl
```

### 4.4 README 轻量复现实测脚本

```bash
psql -d <your_db> -f contrib/pg_faiss/test/bench/bench_cpu_batch_sample.sql
```

### 4.5 GPU 性能 TAP（重负载）

```bash
PG_FAISS_RUN_PERF_GPU=1 \
PG_FAISS_PERF_GPU_ROWS=1000000 \
PG_FAISS_PERF_GPU_DIM=768 \
PG_FAISS_PERF_GPU_QUERIES=100 \
prove -I ./test/perl test/t/030_perf_gpu_vs_pgvector.pl
```

## 5. 说明

- 对比基线版本：pgvector `0.8.2`，FAISS `1.14.1`。
- 重性能基准建议在主分支/夜间流水线执行，不建议每个 PR 默认执行。
- GPU 测试在 GPU 路径不可用时会自动跳过。
- `pg_faiss` 索引注册表为 backend 本地状态；跨会话需要重新创建或加载索引。
