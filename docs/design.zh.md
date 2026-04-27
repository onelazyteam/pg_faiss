# pg_retrieval_engine 设计文档索引

项目内各模块相对独立，后续设计文档按模块维护；本文件只保留总览和发版检查清单。

## 模块设计文档

| 模块 | 文档 | 运行状态 |
|---|---|---|
| FAISS in PostgreSQL | [design/faiss-in-pg.zh.md](design/faiss-in-pg.zh.md) | 已实现 |
| RRF SQL 融合 | [design/rrf-sql.zh.md](design/rrf-sql.zh.md) | 已实现 |
| 评测指标 | [design/evaluation.zh.md](design/evaluation.zh.md) | 离线脚本已实现 |
| 可观测性与自动调参 | [design/observability-autotune.zh.md](design/observability-autotune.zh.md) | FAISS 路径已实现 |
| 后续模块 | [design/future-modules.zh.md](design/future-modules.zh.md) | 脚手架 |

## 发版检查

1. 同步更新 fresh install SQL 与升级 SQL。
2. 执行 `make clean all`、`make install`、`make installcheck`。
3. 对 vector、FTS、RRF 三组结果执行离线评测，至少报告 Recall@K、NDCG@K、P95 latency、P99 latency。
4. 同步 README/API/design 中英文文档。
