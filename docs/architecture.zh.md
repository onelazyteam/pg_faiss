# 架构文档

`pg_retrieval_engine` 的目标是在 PostgreSQL 内提供高性能混合检索引擎。pgvector 是生产一致性 dense 主路径；FAISS 是可选 backend-local 候选加速器，用于候选生成和 benchmark。

```text
业务表
  ├── vector embedding  -> pgvector HNSW / IVFFlat（主路径）
  ├── optional FAISS    -> 候选加速器，结果回表校验
  ├── tsvector          -> PostgreSQL 全文检索
  └── filters           -> tenant / ACL / 标量过滤 / JSONB metadata / 软删除

数据准备
  ├── documents         -> 按 tenant 隔离的多源文本登记
  ├── chunks            -> 稳定 parent-child chunk + citation metadata
  ├── embedding jobs    -> 可 claim 的版本化增量向量化队列
  └── chunk embeddings  -> 每个 chunk、每个 embedding 版本一行

召回结果
  ├── dense ranking
  ├── sparse ranking
  ├── PostgreSQL 回表校验
  └── RRF fusion ranking / 可选 rerank / 面向 Agent 的 chunk 输出

评测与观测
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## 模块

| 模块 | 路径 | 职责 | 状态 |
|---|---|---|---|
| Ingest/chunk/embedding queue | versioned SQL | tenant 隔离文本登记、稳定 chunk upsert、metadata、ACL、embedding 版本与可 claim 任务 | 已实现 v2 |
| Versioned chunk embeddings | versioned SQL | 以 `(chunk_id, embedding_version_id)` 存储多版本 embedding，同时在 chunks 上保留最新向量兼容旧路径 | 已实现 v1 |
| pgvector/FTS hybrid search | versioned SQL | 生产一致性 dense+sparse 召回、tenant/ACL 过滤、批量 wrapper 与 RRF 融合 | 已实现 |
| FAISS in PostgreSQL | `src/faiss_in_pg` | 可选 backend-local FAISS 索引生命周期与查询执行 | 可选加速器 |
| pgvector/FTS index helpers | versioned SQL | 创建 pgvector HNSW/IVFFlat 与 `tsvector` GIN 索引 | 已实现 v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | pgvector 与 `tsvector` 排名融合 | 已实现 |
| metadata、ACL 与行过滤 | versioned SQL | tenant、user、agent、role、namespace、sensitivity、标量、JSONB metadata/ACL、软删除过滤，以及 FAISS 回表校验 | 已实现 v3 |
| FAISS + FTS hybrid | versioned SQL | FAISS 候选与 `tsvector` sparse 双路召回后 RRF，并执行 PostgreSQL 回表校验 | 已实现 v1 |
| Offline evaluation | `evals` | Recall@K、NDCG@K、P95/P99 latency 评测 | 已实现 |
| Benchmark runner | `bench` | 生成 dense/FTS/RRF/rerank/FAISS 报告，并支持带权限违规指标的 Agent context retrieval benchmark | 已实现 v2 |
| Search tool API | `sdk/python` | 底层 hybrid search wrapper，以及返回 context chunks、citations、scores 和 retrieval traces 的 Agent Context API | 已实现 v3 |
| Observability/autotune | versioned SQL + `src/faiss_in_pg` | explain diagnostics、hybrid 参数推荐、FAISS runtime counters | 已实现 |
| Rerank v1 | `src/fts_rerank` + versioned SQL | 基于外部模型/规则分数的候选精排与 citation metadata 输出 | 已实现 |
| Retrieval explain | versioned SQL | 召回阶段计数、重叠、过滤条件、latency hints 和失败原因诊断 | 已实现 v1 |
| disk graph | `src/disk_graph` | 面向大规模向量的磁盘图检索 | 规划中 |

## 运行边界

- pgvector 与 PostgreSQL 表是生产一致性的 source of truth。
- 扩展管理的文档以 `(tenant_id, source_uri)` 隔离；ACL 以 JSONB 保存，并可在检索时通过 `acl_filter` 应用。
- Chunk 使用 `(document_id, chunk_type, chunk_no)` 稳定 upsert。相同位置的 chunk 会保留原 ID；内容变化会清空 chunks 上的最新 embedding，便于 worker 安全重算。
- Embedding worker 应通过 `pg_retrieval_engine_claim_embedding_jobs(...)` 原子 claim 任务，再把返回的 `attempts` 和 `worker_id` 传给 `pg_retrieval_engine_embedding_job_complete(...)` 或 `pg_retrieval_engine_embedding_job_fail(...)`，实现 fenced 写回、状态/内容/维度校验和可重试失败处理。
- `pg_retrieval_engine_activate_embedding_version(...)` 将一个已校验的 embedding 版本提升到 chunks 表的最新向量列，供生产检索路径使用。
- FAISS 索引对象保存在当前 PostgreSQL backend 进程内，不跨 session 共享；仅作为可选候选加速器使用。
- FAISS hybrid search 会把候选 ID join 回 PostgreSQL 业务表后再融合，从而执行过滤和行可见性校验。
- PDF/HTML/Markdown 等解析与 embedding 模型推理在 PostgreSQL 外部执行，扩展接收抽取文本与向量。
- RRF 融合在 SQL/PLpgSQL 层实现，便于独立迭代和评测。
- Rerank 的 cross-encoder 与 LLM 推理在 PostgreSQL 外部执行，扩展只接收分数。
- 评测脚本离线运行，通过 JSONL run 文件对比不同模块。

## 生产化路线

- 保持 pgvector/FTS 作为持久化检索主路径。在共享 sidecar 或 PostgreSQL Index AM 完成前，backend-local FAISS 只作为可选加速器。
- 在 PostgreSQL 外部补 tokenizer-aware、结构感知 chunker，再通过 SQL API 写回稳定 chunk。
- 针对高选择性 tenant/ACL 过滤增加自适应 candidate retry，并在过滤后候选不足时回退 exact path。
- 将 runtime counters 升级为持久化 `pg_stat` 风格观测：按 tenant 的延迟分位数、filter drop rate、rerank latency 和 trace id。

## 文档入口

- API：[api.zh.md](api.zh.md)
- 使用：[usage.zh.md](usage.zh.md)
- Benchmark：[benchmark.zh.md](benchmark.zh.md)
- 模块设计：[design.zh.md](design.zh.md)
