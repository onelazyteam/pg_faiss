# 权衡分析

## Dense-only vs Hybrid Retrieval

dense-only 路径更简单，延迟更容易控制；hybrid retrieval 可以改善关键词、实体词、长尾 query 的召回，但需要额外的全文索引和融合开销。

## In-DB Fusion vs External Rerank

数据库内 RRF 融合便于事务内使用、部署简单、可用 SQL 直接审计；外部 rerank pipeline 更灵活，但引入网络延迟和跨系统一致性问题。

## FAISS Runtime vs PostgreSQL Index AM

当前采用 backend-local FAISS runtime，迭代速度快，适合验证性能与 API；真正的 PostgreSQL Index AM 能获得更完整的 planner/WAL/并发语义，但实现成本更高。

## 验收口径

所有权衡都必须落到量化指标上：

- Recall@K
- NDCG@K
- P95 latency
- P99 latency
- 运维复杂度与恢复成本
