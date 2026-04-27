# 架构文档

`pg_retrieval_engine` 的目标是在 PostgreSQL 内提供完整的混合检索链路：

```text
业务表
  ├── vector embedding  -> pgvector 类型 / FAISS ANN 查询
  ├── tsvector          -> PostgreSQL 全文检索
  └── metadata filters  -> SQL 过滤或 ID allow-list

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
| FAISS in PostgreSQL | `src/faiss_in_pg` | backend-local FAISS 索引生命周期与查询执行 | 已实现 |
| RRF SQL | `src/rrf_sql` + versioned SQL | pgvector 与 `tsvector` 排名融合 | 已实现 |
| Offline evaluation | `evals` | Recall@K、NDCG@K、P95/P99 latency 评测 | 已实现 |
| Observability/autotune | `src/faiss_in_pg` | runtime counters 与搜索参数调优 | 已实现 |
| disk graph | `src/disk_graph` | 面向大规模向量的磁盘图检索 | 规划中 |
| FTS rerank | `src/fts_rerank` | 更完整的稀疏检索 rerank | 规划中 |

## 运行边界

- FAISS 索引对象保存在当前 PostgreSQL backend 进程内，不跨 session 共享。
- 扩展不接管业务表持久化；业务表仍由 PostgreSQL 存储。
- RRF 融合在 SQL/PLpgSQL 层实现，便于独立迭代和评测。
- 评测脚本离线运行，通过 JSONL run 文件对比不同模块。

## 文档入口

- API：[api.zh.md](api.zh.md)
- 使用：[usage.zh.md](usage.zh.md)
- Benchmark：[benchmark.zh.md](benchmark.zh.md)
- 模块设计：[design.zh.md](design.zh.md)
