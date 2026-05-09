# pg_retrieval_engine

中文 | [English](README.md)

`pg_retrieval_engine` 是一个 PostgreSQL 原生高性能混合检索引擎。生产一致性主路径使用 pgvector 做 dense 向量召回，使用 PostgreSQL `tsvector` / GIN 做 sparse 全文召回，并用 SQL RRF 融合 dense+sparse 排名。FAISS 保留为可选候选加速器和 benchmark 路径；FAISS 返回的结果应回表校验 PostgreSQL 行可见性、过滤条件和数据新鲜度。

## 1. 项目内容

### 1.1 做什么

本项目提供以下能力：

| 能力 | 状态 | 说明 |
|---|---|---|
| pgvector 混合检索 | 已实现 | 生产一致性 dense 主路径：pgvector HNSW / IVFFlat + PostgreSQL `tsvector` |
| FAISS in PostgreSQL | 可选加速器 | 在 PostgreSQL backend 内创建、训练、写入、查询 FAISS 索引，用于候选加速和 benchmark |
| FAISS runtime API | 已实现 | 支持 `hnsw`、`ivfflat`、`ivfpq`，支持 `l2`、`ip`、`cosine` |
| 批量检索优化 | 已实现 | 通过 `batch_size` 分块执行，降低大批量查询内存峰值 |
| 过滤检索 | 已实现 | ANN 结果按 `filter_ids` allow-list 过滤 |
| 文档导入与 chunk | 已实现 v2 | 登记按 tenant 隔离的多源文本、稳定 parent-child chunk、metadata、ACL 与 citation metadata |
| Embedding 版本与增量队列 | 已实现 v2 | 管理 embedding model/version，支持 `FOR UPDATE SKIP LOCKED` claim、维度校验和版本化 chunk embedding |
| pgvector 索引管理 | 已实现 v1 | 创建 `pgvector` HNSW / IVFFlat 索引 |
| RRF 融合 | 已实现 | 融合 pgvector 排名与 PostgreSQL `tsvector` 全文检索排名 |
| metadata / 行过滤 | 已实现 v3 | 支持 tenant、user、agent、role、namespace、sensitivity、标量、JSONB metadata/ACL、软删除过滤，以及 FAISS 回表校验 |
| FAISS + FTS 双路召回 | 已实现 v1 | FAISS dense 与 `tsvector` sparse 双路召回后执行 RRF，并执行 PostgreSQL 回表校验 |
| 可观测性 | 已实现 | 暴露 runtime counters、耗时、最近查询参数 |
| 自动调参 | 已实现 | 为 hybrid search 推荐 `latency` / `balanced` / `recall` 模式参数；FAISS runtime 另有默认参数调优 |
| 离线评测 | 已实现 | 计算 Recall@K、NDCG@K、P95/P99 latency |
| Search tool API | 已实现 v3 | 底层 hybrid search wrapper，以及带 context chunks、citations、scores、traces 的 Agent Context API |
| Benchmark runner | 已实现 v2 | 生成 dense/FTS/RRF/rerank/FAISS 报告，并支持带权限违规指标的 Agent context retrieval 报告 |
| Rerank v1 | 已实现 | 基于外部 cross-encoder、LLM 或 rule-based 分数对候选集精排，支持 citation metadata 输出 |
| Retrieval explain | 已实现 v1 | 输出召回阶段计数、重叠情况和 likely failure reason |
| 批量 hybrid 与 chunk search | 已实现 v1 | pgvector/FTS RRF 批量 wrapper，以及面向 Agent 的 `pg_retrieval_engine_search_chunks` 输出 |
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

可选 FAISS runtime 索引：

```sql
SELECT pg_retrieval_engine_index_create(
  'docs_hnsw', 768, 'cosine', 'hnsw',
  '{"m":32,"ef_construction":200,"ef_search":64}'::jsonb,
  'cpu'
);
```

主路径 pgvector + 全文 RRF 融合：

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

带过滤的混合检索：

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
  '{
     "vector_k": 100,
     "fts_k": 100,
     "tenant_id": "acme",
     "acl_filter": {"groups": ["support"]},
     "filters": {"tenant_id": "acme"},
     "metadata_filter": {"doc_type": "manual"},
     "soft_delete_column": "deleted_at"
   }'::jsonb
);
```

面向 Agent 的托管 chunk 检索：

```sql
SELECT chunk_id, context_content, citation_metadata, rrf_score
FROM pg_retrieval_engine_search_chunks(
  '[0.1,0.2,0.3,0.4]'::vector,
  plainto_tsquery('simple', 'vector database'),
  10,
  '{"tenant_id":"acme","acl_filter":{"groups":["support"]},"return_parent":true}'::jsonb
);
```

Agent Context API：

```python
from pg_retrieval_engine_client import AgentContextRetriever, HybridSearchConfig

retriever = AgentContextRetriever(
    connection,
    HybridSearchConfig(table_name="pg_retrieval_engine_chunks"),
    query_embedder=lambda text: embedding_model.embed(text),
)

chunks = retriever.retrieve_context(
    "how should I diagnose replication lag?",
    tenant_id="acme",
    namespace="postgres_runbook",
    top_k=10,
    filters={"doc_type": "runbook"},
    explain=True,
    user_id="alice",
    agent_id="dba-copilot",
    user_roles=["dba"],
    sensitivity_max="internal",
)
```

可选 FAISS 候选加速：

```sql
SELECT *
FROM pg_retrieval_engine_hybrid_search_faiss(
  'documents'::regclass,
  'id',
  'search_vector',
  'docs_hnsw',
  '[0.1,0.2,0.3,0.4]'::vector,
  plainto_tsquery('simple', 'vector database'),
  20,
  '{"vector_k":100,"fts_k":100,"filters":{"tenant_id":"acme"}}'::jsonb
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

Benchmark 报告：

```bash
python3 bench/run_bench.py \
  --qrels evals/qrels.tsv \
  --run dense=results/dense.jsonl \
  --run fts=results/fts.jsonl \
  --run rrf=results/rrf.jsonl \
  --run rerank=results/rerank.jsonl \
  --run faiss=results/faiss.jsonl \
  --ks 10,20 \
  --output results/benchmark.md
```

Agent context benchmark：

```bash
python3 bench/run_agent_context_benchmark.py \
  --qrels evals/agent_qrels.tsv \
  --agent-queries evals/agent_queries.jsonl \
  --run rrf=evals/agent_sample_run.jsonl \
  --ks 5,10 \
  --output results/agent_context_benchmark.md
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
