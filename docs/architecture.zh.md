# 架构文档

`pg_retrieval_engine` 的目标是在 PostgreSQL 内提供完整的混合检索链路：

```text
业务表
  ├── vector embedding  -> pgvector 类型 / FAISS ANN 查询
  ├── tsvector          -> PostgreSQL 全文检索
  └── metadata filters  -> SQL 过滤或 ID allow-list

数据准备
  ├── documents         -> 多源文本登记
  ├── chunks            -> parent-child chunk + citation metadata
  └── embedding jobs    -> 版本化增量向量化队列

召回结果
  ├── dense ranking
  ├── sparse ranking
  └── RRF fusion ranking

评测与观测
  ├── Recall@K / NDCG@K
  ├── P95 / P99 latency
  └── runtime counters / autotune
```

## 模块

| 模块 | 路径 | 职责 | 状态 |
|---|---|---|---|
| Ingest/chunk/embedding queue | versioned SQL | 多源文本登记、chunk、metadata、embedding 版本与增量任务 | 已实现 v1 |
| FAISS in PostgreSQL | `src/faiss_in_pg` | backend-local FAISS 索引生命周期与查询执行 | 已实现 |
| pgvector/FTS index helpers | versioned SQL | 创建 pgvector HNSW/IVFFlat 与 `tsvector` GIN 索引 | 已实现 v1 |
| RRF SQL | `src/rrf_sql` + versioned SQL | pgvector 与 `tsvector` 排名融合 | 已实现 |
| FAISS + FTS hybrid | versioned SQL | FAISS dense 与 `tsvector` sparse 双路召回后 RRF | 已实现 v1 |
| Offline evaluation | `evals` | Recall@K、NDCG@K、P95/P99 latency 评测 | 已实现 |
| Observability/autotune | `src/faiss_in_pg` | runtime counters 与搜索参数调优 | 已实现 |
| Rerank v1 | `src/fts_rerank` + versioned SQL | 基于外部模型/规则分数的候选精排与 citation metadata 输出 | 已实现 |
| Retrieval explain | versioned SQL | 召回阶段计数、重叠和失败原因诊断 | 已实现 v1 |
| disk graph | `src/disk_graph` | 面向大规模向量的磁盘图检索 | 规划中 |

## 运行边界

- FAISS 索引对象保存在当前 PostgreSQL backend 进程内，不跨 session 共享。
- 扩展不接管业务表持久化；业务表仍由 PostgreSQL 存储。
- PDF/HTML/Markdown 等解析与 embedding 模型推理在 PostgreSQL 外部执行，扩展接收抽取文本与向量。
- RRF 融合在 SQL/PLpgSQL 层实现，便于独立迭代和评测。
- Rerank 的 cross-encoder 与 LLM 推理在 PostgreSQL 外部执行，扩展只接收分数。
- 评测脚本离线运行，通过 JSONL run 文件对比不同模块。

## 文档入口

- API：[api.zh.md](api.zh.md)
- 使用：[usage.zh.md](usage.zh.md)
- Benchmark：[benchmark.zh.md](benchmark.zh.md)
- 模块设计：[design.zh.md](design.zh.md)
