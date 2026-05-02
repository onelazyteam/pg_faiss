# 模块设计：后续模块

## `src/disk_graph`

状态：脚手架。

目标职责：

- 面向大规模向量的磁盘图检索。
- 保持与现有函数式 API 兼容。
- 使用同一套离线指标与 FAISS、pgvector 对比。

## `src/fts_rerank`

状态：SQL rerank v1 已实现。

目标职责：

- 在基础候选之外提供 cross-encoder、LLM 和 rule-based 精排能力。
- 支持权重、`none` / `minmax` 归一化和 rerank 诊断信息。
- 与 RRF 输出格式兼容。
- 模型推理不在 PostgreSQL backend 内执行，扩展只接收外部打分结果。

## 集成契约

每个检索模块都应能导出：

- `qid`
- `method`
- 有序结果 ID
- query 级 latency ms

该契约足够支撑 `evals/run_eval.py` 做统一对比。

性能量化测试文档：[../benchmark/future-modules.zh.md](../benchmark/future-modules.zh.md)。
