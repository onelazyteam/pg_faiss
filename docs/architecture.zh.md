# 架构文档

`pg_retrieval_engine` 的目标是在 PostgreSQL 内提供高性能混合检索引擎。pgvector 是生产一致性 dense 主路径；FAISS 是可选 backend-local 候选加速器，用于候选生成和 benchmark。

```text
业务表
  ├── vector embedding  -> pgvector HNSW / IVFFlat（主路径）
  ├── optional FAISS    -> 候选加速器，结果回表校验
  ├── tsvector          -> PostgreSQL 全文检索
  └── filters           -> 标量过滤 / JSONB metadata / 软删除

数据准备
  ├── documents         -> 多源文本登记
  ├── chunks            -> parent-child chunk + citation metadata
  └── embedding jobs    -> 版本化增量向量化队列

召回结果
  ├── dense ranking
  ├── sparse ranking
  ├── PostgreSQL 回表校验
  └── RRF fusion ranking / 可选 rerank

评测与观测
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## 模块

| 模块 | 路径 | 职责 | 状态 |
|---|---|---|---|
| Ingest/chunk/embedding queue | versioned SQL | 多源文本登记、chunk、metadata、embedding 版本与增量任务 | 已实现 v1 |
| pgvector/FTS hybrid search | versioned SQL | 生产一致性 dense+sparse 召回、过滤与 RRF 融合 | 已实现 |
| FAISS in PostgreSQL | `src/faiss_in_pg` | 可选 backend-local FAISS 索引生命周期与查询执行 | 可选加速器 |
| pgvector/FTS index helpers | versioned SQL | 创建 pgvector HNSW/IVFFlat 与 `tsvector` GIN 索引 | 已实现 v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | pgvector 与 `tsvector` 排名融合 | 已实现 |
| metadata 与行过滤 | versioned SQL | 标量过滤、JSONB metadata 过滤、软删除过滤，以及 FAISS 回表校验 | 已实现 v1 |
| FAISS + FTS hybrid | versioned SQL | FAISS 候选与 `tsvector` sparse 双路召回后 RRF，并执行 PostgreSQL 回表校验 | 已实现 v1 |
| Offline evaluation | `evals` | Recall@K、NDCG@K、P95/P99 latency 评测 | 已实现 |
| Benchmark runner | `bench` | 基于导出 run 文件生成 dense/FTS/RRF/rerank/FAISS 对比报告 | 已实现 v1 |
| Search tool API | `sdk/python` | 给应用或 Agent 调用 hybrid search 的轻量 wrapper | 已实现 v1 |
| Observability/autotune | versioned SQL + `src/faiss_in_pg` | explain diagnostics、hybrid 参数推荐、FAISS runtime counters | 已实现 |
| Rerank v1 | `src/fts_rerank` + versioned SQL | 基于外部模型/规则分数的候选精排与 citation metadata 输出 | 已实现 |
| Retrieval explain | versioned SQL | 召回阶段计数、重叠、过滤条件、latency hints 和失败原因诊断 | 已实现 v1 |
| disk graph | `src/disk_graph` | 面向大规模向量的磁盘图检索 | 规划中 |

## 运行边界

- pgvector 与 PostgreSQL 表是生产一致性的 source of truth。
- FAISS 索引对象保存在当前 PostgreSQL backend 进程内，不跨 session 共享；仅作为可选候选加速器使用。
- FAISS hybrid search 会把候选 ID join 回 PostgreSQL 业务表后再融合，从而执行过滤和行可见性校验。
- PDF/HTML/Markdown 等解析与 embedding 模型推理在 PostgreSQL 外部执行，扩展接收抽取文本与向量。
- RRF 融合在 SQL/PLpgSQL 层实现，便于独立迭代和评测。
- Rerank 的 cross-encoder 与 LLM 推理在 PostgreSQL 外部执行，扩展只接收分数。
- 评测脚本离线运行，通过 JSONL run 文件对比不同模块。

## 文档入口

- API：[api.zh.md](api.zh.md)
- 使用：[usage.zh.md](usage.zh.md)
- Benchmark：[benchmark.zh.md](benchmark.zh.md)
- 模块设计：[design.zh.md](design.zh.md)
