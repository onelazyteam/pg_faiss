# pg_faiss v0.2 API 参考

## 1. 说明

- 所有接口都作用于 `pg_faiss` 的 backend 本地索引注册表（非共享全局状态）。
- 主输入类型为 `vector` / `vector[]`（依赖 `pgvector` 扩展）。
- `metric='cosine'` 时，内部走“归一化 + IP”；返回距离会转换为 `1 - inner_product`。
- 当 `k > 当前索引向量数` 时，实际返回条数为 `min(k, ntotal)`。
- `void` 返回函数在 SQL 里是“非 NULL 的 void 值”，用 `IS NOT NULL` 断言成功更直观。

## 2. 函数总览

| 函数 | 作用 | 返回 |
|---|---|---|
| `pg_faiss_index_create` | 创建索引对象并注册到当前 backend | `void` |
| `pg_faiss_index_train` | 训练 IVF/IVFPQ 索引 | `void` |
| `pg_faiss_index_add` | 批量写入向量及显式 ID | `bigint`（写入条数） |
| `pg_faiss_index_search` | 单向量 ANN 检索 | `table(id bigint, distance real)` |
| `pg_faiss_index_search_batch` | 批量向量 ANN 检索 | `table(query_no int, id bigint, distance real)` |
| `pg_faiss_index_save` | 保存索引到磁盘 | `void` |
| `pg_faiss_index_load` | 从磁盘加载索引 | `void` |
| `pg_faiss_index_stats` | 返回索引统计信息 | `jsonb` |
| `pg_faiss_index_drop` | 删除一个索引 | `void` |
| `pg_faiss_reset` | 清空当前 backend 的所有索引 | `void` |

## 3. 接口详情

### 3.1 `pg_faiss_index_create`

签名：

```sql
pg_faiss_index_create(
  name text,
  dim int,
  metric text,
  index_type text,
  options jsonb default '{}'::jsonb,
  device text default 'cpu'
) returns void
```

作用：创建并初始化索引对象。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束/默认 |
|---|---|---|---|---|
| `name` | `text` | 是 | 索引名（当前 backend 内唯一） | 最大 63 字符 |
| `dim` | `int` | 是 | 向量维度 | `1..65535` |
| `metric` | `text` | 是 | 距离度量 | `l2` / `ip` / `inner_product` / `cosine` |
| `index_type` | `text` | 是 | 索引类型 | `hnsw` / `ivfflat` / `ivf_flat` / `ivfpq` / `ivf_pq` |
| `options` | `jsonb` | 否 | 索引构建参数 | 见下表 |
| `device` | `text` | 否 | 运行设备 | `cpu`(默认) / `gpu` |

`options` 支持字段：

| 字段 | 作用 | 默认值 | 范围 |
|---|---|---:|---|
| `m` | HNSW 连边参数 | `32` | `2..256` |
| `ef_construction` | HNSW 构建搜索宽度 | `200` | `4..1000000` |
| `ef_search` | HNSW 默认检索宽度 | `64` | `1..1000000` |
| `nlist` | IVF 聚类中心数 | `4096` | `1..1000000` |
| `nprobe` | IVF 默认探测桶数 | `32` | `1..1000000` |
| `pq_m` | IVFPQ 子量化器数量 | `64` | `1..4096` |
| `pq_bits` | IVFPQ 每子向量 bit 数 | `8` | `1..16` |
| `gpu_device` | GPU 设备编号 | `0` | `0..128` |

常见错误：

- 索引名重复。
- `device='gpu'` 但扩展未用 GPU 编译。
- 参数越界或类型不匹配（例如 `options` 中传非整数）。

### 3.2 `pg_faiss_index_train`

签名：

```sql
pg_faiss_index_train(name text, training_vectors vector[]) returns void
```

作用：训练 IVF/IVFPQ 索引；HNSW 通常无需显式训练（可调用但意义有限）。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束 |
|---|---|---|---|---|
| `name` | `text` | 是 | 索引名 | 必须已存在 |
| `training_vectors` | `vector[]` | 是 | 训练向量集合 | 一维数组、非空、不得含 `NULL`、维度必须等于 `dim` |

常见错误：

- 索引不存在。
- 训练向量为空、维度不一致或有 `NULL`。

### 3.3 `pg_faiss_index_add`

签名：

```sql
pg_faiss_index_add(name text, ids bigint[], vectors vector[]) returns bigint
```

作用：按显式 ID 批量写入向量。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束 |
|---|---|---|---|---|
| `name` | `text` | 是 | 索引名 | 必须已存在 |
| `ids` | `bigint[]` | 是 | 每个向量对应的业务 ID | 一维数组、非空、不得含 `NULL` |
| `vectors` | `vector[]` | 是 | 待写入向量 | 一维数组、非空、不得含 `NULL`、维度一致 |

返回：

- `bigint`，成功写入条数（等于 `vectors` 长度）。

常见错误：

- `ids` 与 `vectors` 数量不一致。
- IVF/IVFPQ 尚未训练（`is_trained=false`）时写入。

### 3.4 `pg_faiss_index_search`

签名：

```sql
pg_faiss_index_search(
  name text,
  query vector,
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(id bigint, distance real)
```

作用：单向量 ANN 检索。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束/默认 |
|---|---|---|---|---|
| `name` | `text` | 是 | 索引名 | 必须已存在 |
| `query` | `vector` | 是 | 查询向量 | 维度必须与索引一致 |
| `k` | `int` | 是 | 返回 top-k | `>0` |
| `search_params` | `jsonb` | 否 | 本次查询参数 | 支持 `ef_search`、`nprobe` |

`search_params` 支持字段：

| 字段 | 对应索引 | 含义 | 范围 |
|---|---|---|---|
| `ef_search` | HNSW | 本次查询搜索宽度 | `1..1000000` |
| `nprobe` | IVF/IVFPQ | 本次查询探测桶数 | `1..1000000` |

返回：

- `id`: 向量 ID（`bigint`）
- `distance`: 距离（`real`）

### 3.5 `pg_faiss_index_search_batch`

签名：

```sql
pg_faiss_index_search_batch(
  name text,
  queries vector[],
  k int,
  search_params jsonb default '{}'::jsonb
) returns table(query_no int, id bigint, distance real)
```

作用：批量 ANN 检索（推荐高吞吐场景使用）。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束 |
|---|---|---|---|---|
| `name` | `text` | 是 | 索引名 | 必须已存在 |
| `queries` | `vector[]` | 是 | 查询向量数组 | 一维、非空、不得含 `NULL`、维度一致 |
| `k` | `int` | 是 | 每个 query 的 top-k | `>0` |
| `search_params` | `jsonb` | 否 | 本次查询参数 | 同 `search` |

返回：

- `query_no`: 输入数组中的 query 序号（从 `1` 开始）
- `id`: 向量 ID
- `distance`: 距离

### 3.6 `pg_faiss_index_save`

签名：

```sql
pg_faiss_index_save(name text, path text) returns void
```

作用：持久化索引。

行为：

- 写入索引主文件：`path`
- 写入元数据文件：`path.meta`

参数：

| 参数 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `name` | `text` | 是 | 索引名 |
| `path` | `text` | 是 | 目标路径 |

### 3.7 `pg_faiss_index_load`

签名：

```sql
pg_faiss_index_load(name text, path text, device text default 'cpu') returns void
```

作用：从磁盘加载索引并注册为新名称。

参数：

| 参数 | 类型 | 必填 | 含义 | 约束/默认 |
|---|---|---|---|---|
| `name` | `text` | 是 | 新索引名 | 当前 backend 中不得已存在 |
| `path` | `text` | 是 | 索引文件路径 | 需可读 |
| `device` | `text` | 否 | 加载后运行设备 | `cpu`(默认) / `gpu` |

说明：

- 若存在 `path.meta`，会优先用其中参数恢复 `metric/index_type` 等信息。
- 若不存在 `path.meta`，会根据索引对象类型推断。

### 3.8 `pg_faiss_index_stats`

签名：

```sql
pg_faiss_index_stats(name text) returns jsonb
```

作用：返回索引状态与参数快照。

关键字段：

- `name`, `version`, `dim`, `metric`, `index_type`, `device`
- `num_vectors`, `is_trained`
- `hnsw.m`, `hnsw.ef_construction`, `hnsw.ef_search`
- `ivf.nlist`, `ivf.nprobe`
- `ivfpq.m`, `ivfpq.bits`
- `index_path`

### 3.9 `pg_faiss_index_drop`

签名：

```sql
pg_faiss_index_drop(name text) returns void
```

作用：删除一个索引并释放资源。

### 3.10 `pg_faiss_reset`

签名：

```sql
pg_faiss_reset() returns void
```

作用：清空当前 backend 中所有 pg_faiss 索引。

## 4. 最小示例

```sql
SELECT pg_faiss_index_create('demo', 4, 'l2', 'hnsw', '{}'::jsonb, 'cpu');
SELECT pg_faiss_index_add('demo', ARRAY[1]::bigint[], ARRAY['[0,1,2,3]'::vector]::vector[]);
SELECT * FROM pg_faiss_index_search('demo', '[0,1,2,3]'::vector, 5, '{}'::jsonb);
SELECT pg_faiss_index_drop('demo');
```
