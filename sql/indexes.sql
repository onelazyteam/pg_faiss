-- Index templates for dense/sparse/hybrid retrieval.
-- Not wired into extension install path.

-- pgvector dense index examples:
-- CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
-- CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 1000);

-- PostgreSQL full-text sparse index:
-- CREATE INDEX ON documents USING gin (search_vector);

-- RRF hybrid search uses both index families through
-- pg_retrieval_engine_hybrid_search(...).
