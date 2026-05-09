# 模块设计：FAISS in PostgreSQL

## 范围

`src/faiss_in_pg` 负责 backend-local 的 FAISS 运行态。在当前产品定位中，pgvector 是生产一致性 dense 主路径，FAISS 是可选候选加速器和 benchmark 路径：

- create / train / add / search / batch search / filtered search。
- FAISS 索引保存与加载。
- CPU 路径与可选 GPU 路径。
- 通过 `pg_retrieval_engine_index_stats` 暴露运行指标。

## 执行模型

索引对象保存在当前 backend 进程内的 hash table 中，key 为索引名。它不是跨 session 共享对象，也不参与 WAL 重放；调用方负责持久化业务数据，本模块负责显式写入向量后的高速检索。

FAISS 结果不是 source of truth。SQL hybrid search 会把 FAISS 候选 ID join 回 PostgreSQL 行后再融合，从而应用行可见性、tenant 过滤、ACL 过滤、标量过滤、metadata 过滤与软删除校验。

单查询路径会临时应用 `ef_search` / `nprobe` / `candidate_k`，执行 FAISS search，再输出 `(id, distance)`。

批查询路径通过 `batch_size` 分块，避免一次性分配 `num_queries * candidate_k` 的大缓冲区。

过滤查询路径使用 “候选集放大 + ID allow-list” 实现，不在 C++ 扩展内部解析任意 SQL 谓词。

## 验证

- 回归测试：生命周期、单查、批查、过滤查、保存加载。
- TAP：召回与 pgvector CPU/GPU 性能对比。
- 离线评测：导出结果后计算 Recall@K、NDCG@K、P95/P99 latency。

性能量化测试文档：[../benchmark/faiss-in-pg.zh.md](../benchmark/faiss-in-pg.zh.md)。
