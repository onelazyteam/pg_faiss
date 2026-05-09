# Agent Context Retrieval Benchmark

This benchmark validates whether retrieval is suitable for Agent and enterprise RAG workflows, not only whether nearest-neighbor ranking looks good.

## Required Metrics

- Context Recall@K: relevant context chunks or documents present in the final context.
- Citation Hit Rate@K: at least one relevant citation appears in the retrieved context.
- Tool-use Context Hit Rate@K: required tool decision context appears before an agent tool call.
- Permission Violation Rate@K: retrieved context that violates the query permission envelope. This must be `0`.
- P95/P99 latency.

## Required Comparison Set

Run the same agent query set against:

- dense-only
- sparse-only
- RRF hybrid
- rerank
- optional FAISS candidate generation

## Dataset Shape

`evals/agent_queries.jsonl`:

```json
{"qid":"agent-q1","tenant_id":"acme","agent_id":"dba-copilot","user_roles":["dba"],"namespace":"postgres_runbook","sensitivity_max":"internal","allowed_doc_ids":["file:///runbooks/replication-lag.md"],"required_tool_context_ids":["tool:check_replication_lag"]}
```

`evals/agent_qrels.tsv`:

```text
agent-q1	file:///runbooks/replication-lag.md	2
```

Run JSONL:

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

Enterprise readiness gate: `Permission Violation Rate@K = 0` for every reported K and every production candidate method.
