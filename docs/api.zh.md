# pg_retrieval_engine API 参考（完整参数版）

## 1. 全局说明

- pgvector 与 PostgreSQL 业务表是生产一致性的 source of truth。
- FAISS 索引对象是 backend-local 可选加速器，不跨 session 全局共享。
- 扩展管理的文档以 `(tenant_id, source_uri)` 隔离；在文档 metadata 和检索 options 中传入 `"tenant_id"`。
- ACL 以 JSONB 存储在 `acl` 字段中，检索时可通过 `acl_filter` 执行包含过滤。
- 输入类型依赖 `pgvector`：`vector` / `vector[]`。
- `metric='cosine'` 使用“归一化 + inner product”；返回值转换为 cosine distance（`1 - ip`）。
- 当 `k > ntotal` 时，实际返回 `min(k, ntotal)`。

## 2. 函数清单

| 函数 | 返回 | 主要用途 |
|---|---|---|
| `pg_retrieval_engine_index_create` | `void` | 创建索引对象 |
| `pg_retrieval_engine_index_train` | `void` | 训练 IVF/IVFPQ |
| `pg_retrieval_engine_index_add` | `bigint` | 批量写入向量 |
| `pg_retrieval_engine_index_search` | `table(id, distance)` | 单向量检索 |
| `pg_retrieval_engine_index_search_batch` | `table(query_no, id, distance)` | 批量检索（优化路径） |
| `pg_retrieval_engine_index_search_filtered` | `table(id, distance)` | 混合检索（单查，ID 过滤） |
| `pg_retrieval_engine_index_search_batch_filtered` | `table(query_no, id, distance)` | 混合检索（批查，ID 过滤） |
| `pg_retrieval_engine_document_upsert` | `bigint` | 登记或更新已抽取的多源文档文本 |
| `pg_retrieval_engine_chunk_document` | `table(...)` | 结构化 chunk、parent-child chunk、metadata/citation metadata |
| `pg_retrieval_engine_embedding_version_create` | `bigint` | 创建或更新 embedding 版本 |
| `pg_retrieval_engine_enqueue_embedding_jobs` | `integer` | 按 chunk content hash 生成增量向量化任务 |
| `pg_retrieval_engine_claim_embedding_jobs` | `table(...)` | 给外部 worker 原子租约 pending、failed 或超时 running embedding 任务 |
| `pg_retrieval_engine_embedding_job_complete` | `void` | 写回外部 worker 生成的 embedding |
| `pg_retrieval_engine_embedding_job_fail` | `void` | 标记 embedding job 失败并释放租约以便重试 |
| `pg_retrieval_engine_activate_embedding_version` | `integer` | 将版本化 chunk embeddings 提升为 chunks 表上的最新向量 |
| `pg_retrieval_engine_pgvector_index_create` | `text` | 创建 pgvector HNSW / IVFFlat 索引 |
| `pg_retrieval_engine_tsvector_index_create` | `text` | 创建 `tsvector` GIN 索引 |
| `pg_retrieval_engine_rrf_fuse` | `table(id, rrf_score, vector_rank, fts_rank)` | 融合两个已排序 ID 列表 |
| `pg_retrieval_engine_hybrid_search` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | pgvector + `tsvector` RRF 混合检索 |
| `pg_retrieval_engine_hybrid_search_batch` | `table(query_no, ...)` | pgvector + `tsvector` RRF 混合检索的批量 wrapper |
| `pg_retrieval_engine_search_chunks` | `table(chunk_id, content, context_content, citation_metadata, ...)` | 面向 Agent/RAG 的扩展托管 chunk 搜索 |
| `pg_retrieval_engine_hybrid_search_faiss` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | FAISS + `tsvector` RRF 混合检索 |
| `pg_retrieval_engine_rerank` | `table(id, final_score, base_rank, base_score, cross_encoder_score, llm_score, rule_score, diagnostics)` | 基于外部模型/规则分数的候选精排 |
| `pg_retrieval_engine_rerank_with_citations` | `table(..., citation, diagnostics)` | 精排并按候选顺序附加 citation metadata |
| `pg_retrieval_engine_retrieval_explain` | `jsonb` | 输出阶段计数、过滤、融合诊断和 likely failure reason |
| `pg_retrieval_engine_hybrid_autotune` | `jsonb` | 为 hybrid search 推荐 latency/balanced/recall 参数 |
| `pg_retrieval_engine_index_autotune` | `jsonb` | 自动调优 FAISS runtime 默认参数 |
| `pg_retrieval_engine_metrics_reset` | `void` | 重置 runtime 指标 |
| `pg_retrieval_engine_index_save` | `void` | 保存索引 |
| `pg_retrieval_engine_index_load` | `void` | 加载索引 |
| `pg_retrieval_engine_index_stats` | `jsonb` | 查看元信息+运行指标 |
| `pg_retrieval_engine_index_drop` | `void` | 删除索引 |
| `pg_retrieval_engine_reset` | `void` | 清空当前 backend 全部索引 |

## 3. 接口详情

### 3.1 `pg_retrieval_engine_index_create`

```sql
pg_retrieval_engine_index_create(
  name text,
  dim int,
  metric text,
  index_type text,
  options jsonb default '{}'::jsonb,
  device text default 'cpu'
) returns void
```

参数：

- `name`: 索引名，当前 backend 内唯一，最长 63 字符。
- `dim`: 维度，范围 `1..65535`。
- `metric`: `l2` / `ip` / `inner_product` / `cosine`。
- `index_type`: `hnsw` / `ivfflat` / `ivf_flat` / `ivfpq` / `ivf_pq`。
- `options`: 索引参数。
- `device`: `cpu`（默认）/ `gpu`。

`options` 字段：

- `m`（HNSW，默认 32）
- `ef_construction`（HNSW，默认 200）
- `ef_search`（HNSW，默认 64）
- `nlist`（IVF，默认 4096）
- `nprobe`（IVF，默认 32）
- `pq_m`（IVFPQ，默认 64）
- `pq_bits`（IVFPQ，默认 8）
- `gpu_device`（GPU 卡号，默认 0）

### 3.2 `pg_retrieval_engine_index_train`

```sql
pg_retrieval_engine_index_train(name text, training_vectors vector[]) returns void
```

- `training_vectors` 需为一维、非空、无 NULL、维度匹配。

### 3.3 `pg_retrieval_engine_index_add`

```sql
pg_retrieval_engine_index_add(name text, ids bigint[], vectors vector[]) returns bigint
```

- `ids` 与 `vectors` 数量必须相同。
- 返回写入条数。

### 3.4 `pg_retrieval_engine_index_search`

```sql
pg_retrieval_engine_index_search(
  name text,
  query vector,
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

`search_params`：

- `ef_search`（HNSW 查询宽度）
- `nprobe`（IVF 探测桶数）
- `candidate_k`（候选集深度，默认 `k`）

### 3.5 `pg_retrieval_engine_index_search_batch`

```sql
pg_retrieval_engine_index_search_batch(
  name text,
  queries vector[],
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

`search_params`：

- `ef_search`
- `nprobe`
- `candidate_k`
- `batch_size`（批处理分块大小，默认使用索引的 `preferred_batch_size`）

### 3.6 `pg_retrieval_engine_index_search_filtered`

```sql
pg_retrieval_engine_index_search_filtered(
  name text,
  query vector,
  k int,
  filter_ids bigint[],
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

作用：ANN 检索后按 `filter_ids` allow-list 过滤，实现混合检索。

### 3.7 `pg_retrieval_engine_index_search_batch_filtered`

```sql
pg_retrieval_engine_index_search_batch_filtered(
  name text,
  queries vector[],
  k int,
  filter_ids bigint[],
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

作用：批量混合检索。每个 query 在过滤后返回 top-k。

### 3.8 数据导入、Chunk 与 Embedding 队列

```sql
pg_retrieval_engine_document_upsert(
  source_uri text,
  source_type text,
  content text,
  metadata jsonb default '{}'::jsonb,
  title text default null
) returns bigint
```

登记或更新外部 parser 已抽取的文本。`source_type` 支持 `technical_doc` / `log` / `sql` / `markdown` / `pdf` / `html` / `text`。PDF/HTML 二进制解析不在 PostgreSQL backend 内执行。

```sql
pg_retrieval_engine_chunk_document(
  document_id bigint,
  chunk_size int default 1000,
  chunk_overlap int default 100,
  options jsonb default '{}'::jsonb
) returns table(chunk_id bigint, parent_chunk_id bigint, chunk_no int, chunk_type text, content text, citation_metadata jsonb)
```

按字符窗口生成 child chunks；`options.parent_chunk_size` 大于 0 时同时生成 parent chunks。每个 chunk 记录 `tenant_id`、`metadata`、`acl`、`citation_metadata`、`search_vector` 和 content hash。

`pg_retrieval_engine_document_upsert` 会读取可选的 `metadata.tenant_id` 和 `metadata.acl`；文档唯一键是 `(tenant_id, source_uri)`。Tenant ID 约束为 `^[A-Za-z0-9_.:-]{1,128}$`，保证 SQL 过滤与 worker 路径的租户表达一致。

`pg_retrieval_engine_chunk_document` 使用 `(document_id, chunk_type, chunk_no)` 做稳定 upsert，不再整篇删除重插。复用同一位置时 chunk ID 保持稳定；如果内容 hash 变化，会清空 chunks 表上的最新 `embedding`，让 worker 安全重算。

```sql
pg_retrieval_engine_embedding_version_create(model_name text, model_version text, dimensions int, distance_metric text default 'cosine', metadata jsonb default '{}'::jsonb, is_active boolean default true) returns bigint
pg_retrieval_engine_enqueue_embedding_jobs(embedding_version_id bigint, only_changed boolean default true) returns integer
pg_retrieval_engine_claim_embedding_jobs(embedding_version_id bigint, batch_size int default 100, worker_id text default null, lease_timeout_seconds int default 900, max_attempts int default 5) returns table(...)
pg_retrieval_engine_embedding_job_complete(job_id bigint, embedding vector, metadata jsonb default '{}'::jsonb, expected_attempt int default null, worker_id text default null) returns void
pg_retrieval_engine_embedding_job_fail(job_id bigint, error_message text, metadata jsonb default '{}'::jsonb, expected_attempt int default null, worker_id text default null) returns void
pg_retrieval_engine_activate_embedding_version(embedding_version_id bigint, tenant_id text default null) returns integer
```

Embedding worker 在 PostgreSQL 外部运行；扩展负责版本记录、增量任务队列和 embedding 写回。`pg_retrieval_engine_claim_embedding_jobs` 使用 `FOR UPDATE SKIP LOCKED` claim pending、failed 或超时 running 任务并递增 `attempts`；它会返回当前 chunk content hash，并在 chunk 已变化时刷新 job hash。`lease_timeout_seconds` 控制租约超时，`max_attempts` 防止无限重试。

`pg_retrieval_engine_embedding_job_complete` 要求 job 已被 claim 且处于 `running`，并校验可选 `expected_attempt`/`worker_id` fencing、拒绝 stale content hash、用 `vector_dims(embedding)` 校验维度，再 upsert 到 `pg_retrieval_engine_chunk_embeddings`。`pg_retrieval_engine_embedding_job_fail` 记录失败诊断，支持同样的可选 fencing，并释放租约。`pg_retrieval_engine_activate_embedding_version` 可按 embedding 版本和可选 tenant 将当前版本化 embedding 提升到 `pg_retrieval_engine_chunks.embedding`，作为生产检索路径使用。

```sql
pg_retrieval_engine_pgvector_index_create(table_name regclass, vector_column name, index_type text, opclass text default 'vector_cosine_ops', options jsonb default '{}'::jsonb) returns text
pg_retrieval_engine_tsvector_index_create(table_name regclass, tsvector_column name) returns text
```

创建 pgvector HNSW / IVFFlat 索引和 `tsvector` GIN 索引。

### 3.9 `pg_retrieval_engine_rrf_fuse`

```sql
pg_retrieval_engine_rrf_fuse(
  vector_ids bigint[],
  fts_ids bigint[],
  k int,
  rrf_k double precision default 60.0,
  vector_weight double precision default 1.0,
  fts_weight double precision default 1.0
) returns table(id bigint, rrf_score double precision, vector_rank int, fts_rank int)
```

作用：对两个已按相关性排序的 ID 列表执行 Reciprocal Rank Fusion。rank 从 1 开始，缺失 rank 贡献 0。

公式：

```text
score = vector_weight / (rrf_k + vector_rank)
      + fts_weight    / (rrf_k + fts_rank)
```

### 3.10 `pg_retrieval_engine_hybrid_search`

```sql
pg_retrieval_engine_hybrid_search(
  table_name regclass,
  id_column name,
  vector_column name,
  tsvector_column name,
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(
  id bigint,
  rrf_score double precision,
  vector_rank int,
  fts_rank int,
  vector_distance real,
  fts_score real
)
```

作用：在同一张表上执行 pgvector 距离排序和 PostgreSQL `tsvector` 全文排序，然后用 RRF 输出统一 top-k。

`options` 字段：

- `vector_k` / `dense_k`：向量候选深度，默认 `k * 4`
- `fts_k` / `sparse_k`：全文候选深度，默认 `k * 4`
- `rrf_k`：RRF 平滑常数，默认 `60`
- `vector_weight` / `dense_weight`：向量结果权重，默认 `1`
- `fts_weight` / `sparse_weight`：全文结果权重，默认 `1`
- `vector_operator`：`<=>`（默认，cosine distance）/ `<->`（L2）/ `<#>`（negative inner product）
- `rank_function`：`ts_rank_cd`（默认）/ `ts_rank`
- `normalization`：全文 rank normalization，默认 `32`
- `tenant_id`：对 `tenant_id` 列执行等值过滤
- `namespace`：对 JSONB metadata 中的 namespace 做等值过滤，面向 Agent/RAG collection
- `agent_id`：仅允许 ACL `agents` 缺省或包含该 agent 的行
- `user_id`：仅允许 ACL `users` 缺省或包含该 user 的行
- `user_roles` / `allowed_roles`：仅允许 ACL `roles` 缺省或与这些角色有交集的行
- `sensitivity_max`：最大可访问敏感级别，取值为 `public`、`internal`、`confidential`、`restricted`
- `filters`：标量列等值过滤，例如 `{"tenant_id":"acme"}`
- `filters` 也支持简单 operator 对象，例如
  `{"status":{"op":"in","value":["active","draft"]}}`、
  `{"deleted_at":{"op":"is_null","value":true}}`、
  `{"properties":{"op":"contains","value":{"doc_type":"manual"}}}`
- `eq`、`ne`、`in`、`contains` operator 必须包含 `value`；空值判断使用 `is_null`
- `metadata_column`：JSONB metadata 列名，默认 `metadata`
- `metadata_filter`：JSONB metadata 过滤。普通值使用包含语义，例如 `{"doc_type":"manual"}`；也支持字段级 operator 对象：
  `{"doc_type":{"op":"in","value":["manual","runbook"]}}`、
  `{"freshness":{"op":"ne","value":"stale"}}`、
  `{"tags":{"op":"contains","value":["postgres"]}}`、
  `{"deprecated":{"op":"is_null","value":true}}`
- `acl_column`：JSONB ACL 列名，默认 `acl`
- `acl_filter`：JSONB 包含过滤，执行为 `acl_column @> acl_filter`
- `soft_delete_column`：软删除标记列，要求该列为 `NULL`

Agent 权限感知检索应传入 top-level 权限字段，而不是只按相似度召回。例如：

```json
{
  "tenant_id": "acme",
  "agent_id": "dba-copilot",
  "user_id": "alice",
  "user_roles": ["dba"],
  "namespace": "postgres_runbook",
  "sensitivity_max": "internal"
}
```

### 3.10.1 `pg_retrieval_engine_hybrid_search_batch`

```sql
pg_retrieval_engine_hybrid_search_batch(
  table_name regclass,
  id_column name,
  vector_column name,
  tsvector_column name,
  query_vectors vector[],
  query_tsqueries tsquery[],
  k int,
  options jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, rrf_score double precision, vector_rank int, fts_rank int, vector_distance real, fts_score real)
```

对多个 query vector / tsquery 执行同一套 hybrid retrieval 契约。当前实现是 `pg_retrieval_engine_hybrid_search` 的 SQL wrapper，主要用于 API 易用性和评测导出，还不是 executor 级共享优化路径。

### 3.10.2 `pg_retrieval_engine_search_chunks`

```sql
pg_retrieval_engine_search_chunks(
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(
  chunk_id bigint,
  document_id bigint,
  parent_chunk_id bigint,
  chunk_type text,
  content text,
  context_content text,
  metadata jsonb,
  citation_metadata jsonb,
  rrf_score double precision,
  vector_rank int,
  fts_rank int,
  vector_distance real,
  fts_score real
)
```

检索 `pg_retrieval_engine_chunks`，强制 `chunk_type='child'`，并返回 content、可选 parent context、metadata、citation 和排名诊断。额外选项：

- `return_parent`：为 `true` 时，若存在 parent chunk，`context_content` 返回 parent 内容；否则返回 child 内容。

### 3.11 `pg_retrieval_engine_hybrid_search_faiss`

```sql
pg_retrieval_engine_hybrid_search_faiss(
  table_name regclass,
  id_column name,
  tsvector_column name,
  faiss_index_name text,
  query_vector vector,
  query_tsquery tsquery,
  k int,
  options jsonb default '{}'::jsonb
) returns table(id bigint, rrf_score double precision, vector_rank int, fts_rank int, vector_distance real, fts_score real)
```

使用 FAISS 索引执行 dense 召回，同时使用 PostgreSQL `tsvector` 执行 sparse 召回。FAISS 返回的候选 ID 会 join 回目标表进行行校验和过滤，然后在 SQL 内执行 RRF。

支持与 `pg_retrieval_engine_hybrid_search` 相同的过滤选项。额外选项：

- `faiss_distance_order`：`asc`（默认）或 `desc`；当 FAISS 路径返回 raw inner product 等“越大越好”的分数时使用 `desc`。

### 3.12 `pg_retrieval_engine_rerank`

```sql
pg_retrieval_engine_rerank(
  candidate_ids bigint[],
  k int,
  cross_encoder_scores double precision[] default null,
  llm_scores double precision[] default null,
  rule_scores double precision[] default null,
  base_scores double precision[] default null,
  options jsonb default '{}'::jsonb
) returns table(
  id bigint,
  final_score double precision,
  base_rank int,
  base_score double precision,
  cross_encoder_score double precision,
  llm_score double precision,
  rule_score double precision,
  diagnostics jsonb
)
```

作用：对已有候选 ID 列表执行精排。cross-encoder 和 LLM 推理由 PostgreSQL 外部的应用或离线服务完成，本函数只接收分数并执行确定性的加权排序。

默认公式：

```text
final_score =
  base_weight * base_component +
  cross_encoder_weight * cross_encoder_score +
  llm_weight * llm_score +
  rule_weight * rule_score
```

如果未传 `base_scores`，`base_component` 使用 `1 / (rank_k + base_rank)`。重复候选 ID 保留第一次出现的位置和对应分数。

`options` 字段：

- `base_weight`：基础 rank/base score 权重，默认 `1`
- `cross_encoder_weight`：cross-encoder 分数权重，默认 `1`
- `llm_weight`：LLM 分数权重，默认 `1`
- `rule_weight`：规则分数权重，默认 `1`
- `rank_k`：基础 rank prior 平滑常数，默认 `60`
- `score_normalization`：`none`（默认）/ `minmax`

`pg_retrieval_engine_rerank_with_citations(...)` 与 `pg_retrieval_engine_rerank(...)` 使用同一打分参数，并额外接收 `citation_metadata jsonb[]`，按输入候选顺序把 citation 附加到精排结果。

### 3.13 `pg_retrieval_engine_retrieval_explain`

```sql
pg_retrieval_engine_retrieval_explain(
  vector_ids bigint[] default ARRAY[]::bigint[],
  fts_ids bigint[] default ARRAY[]::bigint[],
  final_ids bigint[] default ARRAY[]::bigint[],
  relevant_ids bigint[] default null,
  options jsonb default '{}'::jsonb
) returns jsonb
```

返回 `stage_counts`、候选重叠、过滤诊断、可选 latency hints、`relevance.recalled`、`relevance.missing` 和 `likely_failure_reason`。v1 reason 包含 `no_final_results`、`no_relevance_labels`、`fully_recalled`、`fusion_or_rerank_drop`、`candidate_generation_miss`。

在 Agent debugging 中，这个输出就是 retrieval trace 的来源。Trace 页面可以展示 user query、retrieval options、dense top K、sparse top K、RRF overlap、rerank result、调用方导出的 filtered-out docs、final context 和 likely failure reason。

### 3.14 `pg_retrieval_engine_hybrid_autotune`

```sql
pg_retrieval_engine_hybrid_autotune(
  mode text default 'balanced',
  k int default 10,
  options jsonb default '{}'::jsonb
) returns jsonb
```

返回 `vector_k`、`fts_k`、`rrf_k`、可选 `rerank_k` 以及 pgvector runtime 参数的启发式推荐。输出只是起点，必须用固定 qrels 和 P95/P99 latency 复测。

支持 `mode`：`latency` / `balanced` / `recall`。

支持 `options`：

- `target_recall`，默认 `0.90`
- `target_p95_ms`，可选
- `max_candidate_k`，默认 `1000`
- `vector_weight`、`fts_weight`

### 3.15 `pg_retrieval_engine_index_autotune`

```sql
pg_retrieval_engine_index_autotune(
  name text,
  mode text default 'balanced',
  options jsonb default '{}'::jsonb
) returns jsonb
```

参数：

- `mode`: `latency` / `balanced` / `recall`
- `options`:
  - `target_recall`（默认 0.95）
  - `min_batch_size`（默认 32）
  - `max_batch_size`（默认 4096）

返回：包含 `hnsw_ef_search` / `ivf_nprobe` / `preferred_batch_size` 的 old/new 对比。

### 3.16 `pg_retrieval_engine_metrics_reset`

```sql
pg_retrieval_engine_metrics_reset(name text default null) returns void
```

- `name is null`：重置当前 backend 全部索引 runtime 指标。
- `name not null`：只重置目标索引 runtime 指标。

### 3.17 `pg_retrieval_engine_index_save`

```sql
pg_retrieval_engine_index_save(name text, path text) returns void
```

- 主索引写到 `path`
- 元数据写到 `path.meta`

### 3.18 `pg_retrieval_engine_index_load`

```sql
pg_retrieval_engine_index_load(name text, path text, device text default 'cpu') returns void
```

- 将磁盘索引加载为新索引名。

### 3.19 `pg_retrieval_engine_index_stats`

```sql
pg_retrieval_engine_index_stats(name text) returns jsonb
```

包含三类信息：

- 元信息：`name/version/dim/metric/index_type/device`
- 参数：`hnsw/ivf/ivfpq`
- 运行指标：`runtime.*`（调用量、耗时、候选深度、batch 参数、autotune 状态等）

### 3.20 `pg_retrieval_engine_index_drop`

```sql
pg_retrieval_engine_index_drop(name text) returns void
```

### 3.21 `pg_retrieval_engine_reset`

```sql
pg_retrieval_engine_reset() returns void
```

### RRF 融合

```sql
SELECT *
FROM pg_retrieval_engine_hybrid_search(
  'documents'::regclass,
  'id',
  'embedding',
  'search_vector',
  '[0.1,0.2,0.3,0.4]'::vector,
  plainto_tsquery('simple', 'vector database'),
  20,
  '{"vector_k":100,"fts_k":100,"rrf_k":60,"vector_operator":"<=>"}'::jsonb
);
```

## 4. 常见错误

- 参数类型或范围非法：`ERRCODE_INVALID_PARAMETER_VALUE`
- 索引不存在：`ERRCODE_UNDEFINED_OBJECT`
- 状态非法（例如未训练就写入 IVF）：`ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE`
- FAISS 运行异常：`ERRCODE_EXTERNAL_ROUTINE_EXCEPTION`

## 5. 混合检索示例（工业常见模式）

```sql
WITH allow_list AS (
  SELECT array_agg(id ORDER BY id) AS ids
  FROM product_embedding
  WHERE tenant_id = 42
    AND category = 'electronics'
    AND is_active = true
)
SELECT *
FROM pg_retrieval_engine_index_search_filtered(
  'prod_idx',
  '[0.1,0.2,0.3,0.4]'::vector,
  20,
  (SELECT ids FROM allow_list),
  '{"candidate_k":200,"ef_search":128}'::jsonb
);
```
