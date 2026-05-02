# pg_retrieval_engine API 参考（完整参数版）

## 1. 全局说明

- 所有索引对象都存在于当前 PostgreSQL backend 进程内（非全局共享）。
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
| `pg_retrieval_engine_embedding_job_complete` | `void` | 写回外部 worker 生成的 embedding |
| `pg_retrieval_engine_pgvector_index_create` | `text` | 创建 pgvector HNSW / IVFFlat 索引 |
| `pg_retrieval_engine_tsvector_index_create` | `text` | 创建 `tsvector` GIN 索引 |
| `pg_retrieval_engine_rrf_fuse` | `table(id, rrf_score, vector_rank, fts_rank)` | 融合两个已排序 ID 列表 |
| `pg_retrieval_engine_hybrid_search` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | pgvector + `tsvector` RRF 混合检索 |
| `pg_retrieval_engine_hybrid_search_faiss` | `table(id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score)` | FAISS + `tsvector` RRF 混合检索 |
| `pg_retrieval_engine_rerank` | `table(id, final_score, base_rank, base_score, cross_encoder_score, llm_score, rule_score, diagnostics)` | 基于外部模型/规则分数的候选精排 |
| `pg_retrieval_engine_rerank_with_citations` | `table(..., citation, diagnostics)` | 精排并按候选顺序附加 citation metadata |
| `pg_retrieval_engine_retrieval_explain` | `jsonb` | 输出召回阶段计数和 likely failure reason |
| `pg_retrieval_engine_index_autotune` | `jsonb` | 自动调参 |
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

按字符窗口生成 child chunks；`options.parent_chunk_size` 大于 0 时同时生成 parent chunks。每个 chunk 记录 `metadata`、`citation_metadata`、`search_vector` 和 content hash。

```sql
pg_retrieval_engine_embedding_version_create(model_name text, model_version text, dimensions int, distance_metric text default 'cosine', metadata jsonb default '{}'::jsonb, is_active boolean default true) returns bigint
pg_retrieval_engine_enqueue_embedding_jobs(embedding_version_id bigint, only_changed boolean default true) returns integer
pg_retrieval_engine_embedding_job_complete(job_id bigint, embedding vector, metadata jsonb default '{}'::jsonb) returns void
```

Embedding worker 在 PostgreSQL 外部运行；扩展负责版本记录、增量任务队列和 embedding 写回。

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

使用 FAISS 索引执行 dense 召回，同时使用 PostgreSQL `tsvector` 执行 sparse 召回，然后在 SQL 内执行 RRF。

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

返回 `stage_counts`、`relevance.recalled`、`relevance.missing` 和 `likely_failure_reason`。v1 reason 包含 `no_final_results`、`no_relevance_labels`、`fully_recalled`、`fusion_or_rerank_drop`、`candidate_generation_miss`。

### 3.14 `pg_retrieval_engine_index_autotune`

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

### 3.15 `pg_retrieval_engine_metrics_reset`

```sql
pg_retrieval_engine_metrics_reset(name text default null) returns void
```

- `name is null`：重置当前 backend 全部索引 runtime 指标。
- `name not null`：只重置目标索引 runtime 指标。

### 3.16 `pg_retrieval_engine_index_save`

```sql
pg_retrieval_engine_index_save(name text, path text) returns void
```

- 主索引写到 `path`
- 元数据写到 `path.meta`

### 3.17 `pg_retrieval_engine_index_load`

```sql
pg_retrieval_engine_index_load(name text, path text, device text default 'cpu') returns void
```

- 将磁盘索引加载为新索引名。

### 3.18 `pg_retrieval_engine_index_stats`

```sql
pg_retrieval_engine_index_stats(name text) returns jsonb
```

包含三类信息：

- 元信息：`name/version/dim/metric/index_type/device`
- 参数：`hnsw/ivf/ivfpq`
- 运行指标：`runtime.*`（调用量、耗时、候选深度、batch 参数、autotune 状态等）

### 3.19 `pg_retrieval_engine_index_drop`

```sql
pg_retrieval_engine_index_drop(name text) returns void
```

### 3.20 `pg_retrieval_engine_reset`

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
