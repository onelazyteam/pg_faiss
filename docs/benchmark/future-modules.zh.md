# 性能量化测试：后续模块

## 范围

本文定义 `disk_graph`、`fts_rerank` 等规划模块的 benchmark 契约。

## 实现前必须明确

每个新模块必须先定义：

- 对比基线模块
- 目标数据规模
- 查询集
- qrels 格式
- Recall@K 目标
- 有 graded relevance 时的 NDCG@K 目标
- P95/P99 latency 预算
- 与 `evals/run_eval.py` 兼容的导出格式

## 必报结果

新模块必须和已有基线一起报告：

- FAISS 路径
- 适用时报告 pgvector 路径
- 适用时报告 FTS 路径
- 适用时报告 RRF 路径
