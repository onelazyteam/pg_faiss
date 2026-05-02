# pg_retrieval_engine

中文 | [English](README.md)

`pg_retrieval_engine` 是一个面向 PostgreSQL 的混合检索扩展，目标是在数据库内组合向量检索、全文检索、融合排序、评测与可观测能力。当前版本以 FAISS 作为高性能 ANN 执行引擎，复用 pgvector 的 `vector` 类型，并通过 PostgreSQL 原生 `tsvector` 支持全文检索，再用 RRF 将 dense/sparse 结果融合。

## 1. 项目内容

### 1.1 做什么

本项目提供以下能力：

| 能力 | 状态 | 说明 |
|---|---|---|
| FAISS in PostgreSQL | 已实现 | 在 PostgreSQL backend 内创建、训练、写入、查询 FAISS 索引 |
| 向量检索 API | 已实现 | 支持 `hnsw`、`ivfflat`、`ivfpq`，支持 `l2`、`ip`、`cosine` |
| 批量检索优化 | 已实现 | 通过 `batch_size` 分块执行，降低大批量查询内存峰值 |
| 过滤检索 | 已实现 | ANN 结果按 `filter_ids` allow-list 过滤 |
| 文档导入与 chunk | 已实现 v1 | 登记多源文本、结构化 chunk、parent-child chunk、metadata/citation metadata |
| Embedding 版本与增量队列 | 已实现 v1 | 管理 embedding model/version，按 chunk content hash 生成增量向量化任务 |
| pgvector 索引管理 | 已实现 v1 | 创建 `pgvector` HNSW / IVFFlat 索引 |
| RRF 融合 | 已实现 | 融合 pgvector 排名与 PostgreSQL `tsvector` 全文检索排名 |
| FAISS + FTS 双路召回 | 已实现 v1 | FAISS dense 与 `tsvector` sparse 双路召回后执行 RRF |
| 可观测性 | 已实现 | 暴露 runtime counters、耗时、最近查询参数 |
| 自动调参 | 已实现 | `latency` / `balanced` / `recall` 模式调整搜索默认参数 |
| 离线评测 | 已实现 | 计算 Recall@K、NDCG@K、P95/P99 latency |
| Rerank v1 | 已实现 | 基于外部 cross-encoder、LLM 或 rule-based 分数对候选集精排，支持 citation metadata 输出 |
| Retrieval explain | 已实现 v1 | 输出召回阶段计数、重叠情况和 likely failure reason |
| disk graph | 规划中 | 面向更大规模向量的磁盘图检索模块 |

### 1.2 目录结构

```text
contrib/pg_retrieval_engine/
├── README.md / README.zh.md        # 项目总览
├── Makefile                        # PGXS 构建入口
├── pg_retrieval_engine.control     # PostgreSQL 扩展元信息
├── sql/                            # 扩展安装/升级 SQL 与 SQL 模板
├── src/
│   ├── faiss_in_pg/                # FAISS C++ 执行引擎
│   ├── rrf_sql/                    # RRF SQL 融合模块说明
│   ├── disk_graph/                 # 规划中的磁盘图检索模块
│   └── fts_rerank/                 # SQL rerank v1 模块说明
├── docs/                           # 架构、API、使用、benchmark、模块设计文档
├── evals/                          # 离线评测脚本、qrels、样例 run 文件
├── bench/                          # benchmark/ablation 脚本入口
├── test/                           # 回归测试与 TAP 测试
├── demo/                           # demo 脚手架
└── site/                           # GitHub Pages 站点源码
```

### 1.3 模块与量化指标

| 模块 | 方向 | 必看指标 | 当前目标/结果 |
|---|---|---|---|
| FAISS in PostgreSQL | ANN 向量检索 | Recall@10、avg latency、P95/P99 latency、pgvector speedup | CPU 目标 `>=5x`；本机 batch HNSW 实测 `11.32x`，IVFFlat 实测 `10.31x` |
| RRF SQL | 混合检索融合 | Recall@K、NDCG@K、P95/P99 latency、vector/FTS/RRF ablation | 必须同时报告 vector-only、FTS-only、RRF 三组结果 |
| Ingest/Chunk/Embedding 队列 | 数据准备 | chunk 数量、增量任务数、metadata/citation 完整性 | 外部 parser/embedding worker 与 SQL API 解耦 |
| 可观测性/自动调参 | 线上运行质量 | search calls、avg latency、last_candidate_k、preferred_batch_size、调参前后 Recall/Latency | 调参前后必须用统一 qrels 复测 |
| 离线评测 | 质量验收 | Recall@K、NDCG@K、latency_p95_ms、latency_p99_ms | `evals/run_eval.py` 已支持 |
| Rerank v1 | 候选精排 | Recall@K、NDCG@K、P95/P99 latency、rerank ablation | 对比 base、cross-encoder、LLM 与 rule-based 变体 |
| disk graph | 后续模块 | 与 FAISS/RRF 相同的质量与尾延迟指标 | 进入实现前先补独立 benchmark 文档 |

## 2. 编译安装

### 2.1 依赖

- PostgreSQL 18.3
- pgvector 0.8.2
- FAISS 1.14.1
- C++17 编译器

macOS CPU FAISS 示例：

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

### 2.2 构建扩展

```bash
cd contrib/pg_retrieval_engine
make \
  PG_CPPFLAGS="-I$HOME/faiss-install/include -I/usr/local/opt/libomp/include -std=c++17" \
  SHLIB_LINK="-L$HOME/faiss-install/lib -lfaiss -L/usr/local/opt/libomp/lib -lomp -framework Accelerate -lc++ -lc++abi -bundle_loader $(pg_config --bindir)/postgres"
make install
```

GPU 构建：

```bash
make USE_FAISS_GPU=1 FAISS_GPU_LIBS="-lfaiss -lcudart -lcublas"
make install
```

### 2.3 启用扩展

```sql
CREATE EXTENSION vector;
CREATE EXTENSION pg_retrieval_engine;
```

## 3. 使用入口

向量索引：

```sql
SELECT pg_retrieval_engine_index_create(
  'docs_hnsw', 768, 'cosine', 'hnsw',
  '{"m":32,"ef_construction":200,"ef_search":64}'::jsonb,
  'cpu'
);
```

RRF 融合：

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

离线评测：

```bash
python3 evals/run_eval.py \
  --qrels evals/qrels.tsv \
  --run results/vector.jsonl \
  --run results/fts.jsonl \
  --run results/rrf.jsonl \
  --ks 10,20,100
```

## 4. 文档

| 类型 | 中文 | English |
|---|---|---|
| 架构 | [docs/architecture.zh.md](docs/architecture.zh.md) | [docs/architecture.md](docs/architecture.md) |
| API | [docs/api.zh.md](docs/api.zh.md) | [docs/api.md](docs/api.md) |
| 使用 | [docs/usage.zh.md](docs/usage.zh.md) | [docs/usage.md](docs/usage.md) |
| Benchmark | [docs/benchmark.zh.md](docs/benchmark.zh.md) | [docs/benchmark.md](docs/benchmark.md) |
| 模块设计 | [docs/design.zh.md](docs/design.zh.md) | [docs/design.md](docs/design.md) |

## 5. 测试

```bash
make installcheck
prove -I ./test/perl test/t/010_recall.pl
```

重负载 benchmark：

```bash
pg_retrieval_engine_RUN_PERF=1 \
pg_retrieval_engine_PERF_ROWS=1000000 \
pg_retrieval_engine_PERF_DIM=768 \
pg_retrieval_engine_PERF_QUERIES=100 \
prove -I ./test/perl test/t/020_perf_cpu_vs_pgvector.pl
```
