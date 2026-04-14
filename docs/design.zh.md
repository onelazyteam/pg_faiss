# pg_faiss v0.2 设计文档

## 1. 目标

- 以函数式接口集成 FAISS，不实现新的 PostgreSQL Index AM。
- 以 `vector` / `vector[]` 作为主数据通道，减少数组拆解与拷贝开销。
- 支持 CPU 与可选 GPU 两种运行路径。
- 通过 FAISS 二进制文件 + 轻量元数据文件实现可恢复持久化。

## 1.1 对比基线与依赖版本

- PostgreSQL：18.3
- pgvector：0.8.2（本期性能对比基线版本）
- FAISS：1.14.1（CPU，GPU 为可选构建）

FAISS CPU 安装约定（详细命令见 `docs/usage.zh.md`）：
- `FAISS_ENABLE_GPU=OFF`
- `CMAKE_BUILD_TYPE=Release`
- 安装前缀建议：`$HOME/faiss-install`

## 2. 架构

### 2.1 核心组件

- 扩展入口：`src/pg_faiss.cpp`
- 索引注册表：按索引名管理的 backend 本地哈希表（`PgFaissIndexEntry`）
- 运行时索引对象：
  - 必有 CPU 索引（`faiss::Index*`）
  - 当 `device='gpu'` 且构建启用 GPU 时，维护 GPU 克隆索引

### 2.2 数据流

1. `pg_faiss_index_create`
- 解析 `metric`、`index_type`、`options`、`device`
- 构建 FAISS 索引（`HNSW` / `IVFFlat` / `IVFPQ`）
- 用 `IndexIDMap2` 包装以支持显式 ID

2. `pg_faiss_index_train`
- 将 `vector[]` 转成连续 float 缓冲区
- cosine 度量下先归一化
- 训练 IVF 系列索引

3. `pg_faiss_index_add`
- 解析 `ids bigint[]` 和 `vectors vector[]`
- 通过 `IndexIDMap2` 批量写入

4. `pg_faiss_index_search` / `pg_faiss_index_search_batch`
- 解析 `search_params`（`ef_search`、`nprobe`）
- 临时应用检索参数并执行查询
- 以表结构返回结果

5. `pg_faiss_index_save` / `pg_faiss_index_load`
- 保存 FAISS 索引二进制（`write_index`）
- 旁路保存 `<path>.meta` 元数据
- 加载二进制 + 元数据并重建运行态

## 3. API 列表

| 函数 | 说明 |
|---|---|
| `pg_faiss_index_create` | 创建索引与运行参数 |
| `pg_faiss_index_train` | 训练 IVF 索引 |
| `pg_faiss_index_add` | 批量写入（显式 ID） |
| `pg_faiss_index_search` | 单查询 ANN 检索 |
| `pg_faiss_index_search_batch` | 批查询 ANN 检索 |
| `pg_faiss_index_save` | 持久化索引与元数据 |
| `pg_faiss_index_load` | 加载持久化索引 |
| `pg_faiss_index_stats` | 返回 `jsonb` 统计信息 |
| `pg_faiss_index_drop` | 删除单个索引 |
| `pg_faiss_reset` | 清空当前 backend 的全部索引 |

## 4. 默认参数

- HNSW：`m=32`、`ef_construction=200`、`ef_search=64`
- IVFFlat：`nlist=4096`、`nprobe=32`
- IVFPQ：`nlist=4096`、`pq_m=64`、`pq_bits=8`、`nprobe=32`
- 度量：`l2`、`ip`、`cosine`（`cosine` 采用归一化 + IP）

## 5. 测试策略

- `pg_regress`：覆盖 create/train/add/search/save/load/drop/reset 主流程。
- TAP Recall：与精确基线比对，要求 `Recall@10 >= 0.95`。
- TAP 性能：
  - CPU：对比 pgvector HNSW/IVFFlat，默认目标 5x
  - GPU：条件执行，默认目标 10x

### 5.1 性能方法学

- 验收口径：同机、同数据集、同查询集、同召回约束（`Recall@10 >= 95%`）。
- CPU 门槛：`>=5x`；GPU 门槛：`>=10x`。
- 重负载验收集：`1M x 768`（由 `test/t/020_perf_cpu_vs_pgvector.pl` 与 `test/t/030_perf_gpu_vs_pgvector.pl` 执行）。
- README 轻量复现实测：`contrib/pg_faiss/test/bench/bench_cpu_batch_sample.sql`（`20,000 x 128`）。

### 5.2 本机 CPU 实测快照（2026-04-14，批量查询路径）

- 数据规模：`20,000 x 128`，`29` queries，`k=10`
- 基线：pgvector 0.8.2
- 参数：pgvector `hnsw.ef_search=512`、`ivfflat.probes=16`；pg_faiss `ef_search=128`、`nprobe=16`
- 结果：
  - HNSW：`11.32x`（pgvector `1.13 ms` vs pg_faiss(batch) `0.10 ms`，Recall@10：`0.9552` vs `1.0`）
  - IVFFlat：`10.31x`（pgvector `0.76 ms` vs pg_faiss(batch) `0.07 ms`，Recall@10 均为 `1.0`）

## 6. CI 策略

- PR/默认流水线：跑正确性 + recall。
- 主分支/夜间任务：通过环境变量启用重基准：
  - `PG_FAISS_RUN_PERF=1`
  - `PG_FAISS_RUN_PERF_GPU=1`
