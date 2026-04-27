# 模块设计：FAISS in PostgreSQL

## 范围

`src/faiss_in_pg` 负责 backend-local 的 FAISS 运行态：

- create / train / add / search / batch search / filtered search。
- FAISS 索引保存与加载。
- CPU 路径与可选 GPU 路径。
- 通过 `pg_retrieval_engine_index_stats` 暴露运行指标。

## 执行模型

索引对象保存在当前 backend 进程内的 hash table 中，key 为索引名。它不是跨 session 共享对象，也不参与 WAL 重放；调用方负责持久化业务数据，本模块负责显式写入向量后的高速检索。

单查询路径会临时应用 `ef_search` / `nprobe` / `candidate_k`，执行 FAISS search，再输出 `(id, distance)`。

批查询路径通过 `batch_size` 分块，避免一次性分配 `num_queries * candidate_k` 的大缓冲区。

过滤查询路径使用 “候选集放大 + ID allow-list” 实现，不在 C++ 扩展内部解析任意 SQL 谓词。

## 验证

- 回归测试：生命周期、单查、批查、过滤查、保存加载。
- TAP：召回与 pgvector CPU/GPU 性能对比。
- 离线评测：导出结果后计算 Recall@K、NDCG@K、P95/P99 latency。

性能量化测试文档：[../benchmark/faiss-in-pg.zh.md](../benchmark/faiss-in-pg.zh.md)。
