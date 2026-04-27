# Tradeoffs

## Dense-only vs Hybrid Retrieval

Dense-only retrieval is simpler and easier to keep low-latency. Hybrid retrieval
can improve keyword, entity, and long-tail queries, but requires a full-text
index and pays SQL fusion cost.

## In-DB Fusion vs External Rerank

In-database RRF fusion is easier to deploy, usable inside SQL workflows, and
auditable with query plans. External rerank pipelines are more flexible, but add
network latency and cross-system consistency concerns.

## FAISS Runtime vs PostgreSQL Index AM

The current backend-local FAISS runtime is fast to iterate and useful for API and
performance validation. A full PostgreSQL Index AM would integrate better with
planner, WAL, and concurrency semantics, but costs substantially more to build.

## Acceptance Criteria

Every tradeoff should be judged with quantitative metrics:

- Recall@K
- NDCG@K
- P95 latency
- P99 latency
- operational complexity and recovery cost
