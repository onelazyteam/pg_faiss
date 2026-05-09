# Agent Context Retrieval Benchmark

这个 benchmark 验证检索是否适合 Agent 和企业 RAG workflow，而不只是最近邻排序是否好看。

## 必报指标

- Context Recall@K：最终上下文中是否包含相关 context chunk 或文档。
- Citation Hit Rate@K：召回上下文中是否命中相关 citation。
- Tool-use Context Hit Rate@K：Agent 调用工具前是否拿到了必要决策上下文。
- Permission Violation Rate@K：召回结果中违反 query 权限边界的比例。该指标必须为 `0`。
- P95/P99 latency。

## 必跑对比

同一组 agent query 需要比较：

- dense-only
- sparse-only
- RRF hybrid
- rerank
- 可选 FAISS candidate generation

## 数据集格式

`evals/agent_queries.jsonl`：

```json
{"qid":"agent-q1","tenant_id":"acme","agent_id":"dba-copilot","user_roles":["dba"],"namespace":"postgres_runbook","sensitivity_max":"internal","allowed_doc_ids":["file:///runbooks/replication-lag.md"],"required_tool_context_ids":["tool:check_replication_lag"]}
```

`evals/agent_qrels.tsv`：

```text
agent-q1	file:///runbooks/replication-lag.md	2
```

Run JSONL：

```json
{"qid":"agent-q1","method":"rrf","latency_ms":5.2,"results":[{"id":"file:///runbooks/replication-lag.md","rank":1,"citation_id":"file:///runbooks/replication-lag.md","tool_context_id":"tool:check_replication_lag","permission_allowed":true}]}
```

## Runner

```bash
python3 bench/run_agent_context_benchmark.py \
  --qrels evals/agent_qrels.tsv \
  --agent-queries evals/agent_queries.jsonl \
  --run dense=results/agent_dense.jsonl \
  --run sparse=results/agent_sparse.jsonl \
  --run rrf=results/agent_rrf.jsonl \
  --run rerank=results/agent_rerank.jsonl \
  --ks 5,10 \
  --output results/agent_context_benchmark.md
```

企业可用性门槛：每个 K、每个生产候选方法的 `Permission Violation Rate@K = 0`。
