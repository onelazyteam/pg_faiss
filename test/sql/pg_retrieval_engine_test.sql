CREATE EXTENSION vector;
CREATE EXTENSION pg_retrieval_engine;

SELECT pg_retrieval_engine_reset() IS NOT NULL AS reset_ok;

\pset format unaligned

SELECT pg_retrieval_engine_document_upsert(
    'file:///docs/retrieval.md',
    'markdown',
    'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda',
    '{"repo":"demo","path":"docs/retrieval.md"}'::jsonb,
    'Retrieval Doc'
) > 0 AS document_upsert_ok;

SELECT count(*) FILTER (WHERE chunk_type = 'parent') AS parent_chunks,
       count(*) FILTER (WHERE chunk_type = 'child') AS child_chunks,
       bool_and(citation_metadata ? 'source_uri') AS has_citations
FROM pg_retrieval_engine_chunk_document(
    (SELECT id FROM pg_retrieval_engine_documents WHERE source_uri = 'file:///docs/retrieval.md'),
    20,
    5,
    '{"parent_chunk_size":40}'::jsonb
);

SELECT pg_retrieval_engine_embedding_version_create(
    'demo-embed',
    'v1',
    4,
    'cosine',
    '{"provider":"test"}'::jsonb
) > 0 AS embedding_version_ok;

SELECT pg_retrieval_engine_enqueue_embedding_jobs(
    (SELECT id FROM pg_retrieval_engine_embedding_versions WHERE model_name = 'demo-embed' AND model_version = 'v1')
) > 0 AS embedding_jobs_enqueued;

SELECT pg_retrieval_engine_embedding_job_complete(
    (SELECT min(id) FROM pg_retrieval_engine_embedding_jobs),
    '[1,0,0,0]'::vector,
    '{"source":"regress"}'::jsonb
) IS NOT NULL AS embedding_job_complete_ok;

SELECT count(*) FILTER (WHERE embedding IS NOT NULL) AS embedded_chunks,
       count(*) FILTER (WHERE status = 'done') AS done_jobs
FROM pg_retrieval_engine_chunks c
LEFT JOIN pg_retrieval_engine_embedding_jobs j ON j.chunk_id = c.id;

\pset format aligned

SELECT pg_retrieval_engine_index_create(
    'idx_h',
    4,
    'l2',
    'hnsw',
    '{"m":16,"ef_construction":128,"ef_search":128}'::jsonb,
    'cpu'
) IS NOT NULL AS create_hnsw_ok;

SELECT pg_retrieval_engine_index_add(
    'idx_h',
    ARRAY[1,2,3,4]::bigint[],
    ARRAY[
        '[1,0,0,0]'::vector,
        '[2,0,0,0]'::vector,
        '[3,0,0,0]'::vector,
        '[4,0,0,0]'::vector
    ]::vector[]
) AS added_hnsw;

SELECT (pg_retrieval_engine_index_stats('idx_h')->>'num_vectors')::int AS hnsw_num_vectors;

SELECT id
FROM pg_retrieval_engine_index_search('idx_h', '[1,0,0,0]'::vector, 2, '{}'::jsonb)
ORDER BY distance, id;

SELECT id
FROM pg_retrieval_engine_index_search_filtered(
    'idx_h',
    '[1,0,0,0]'::vector,
    2,
    ARRAY[2,4]::bigint[],
    '{"candidate_k":4}'::jsonb
)
ORDER BY distance, id;

SELECT count(*) AS batch_rows
FROM pg_retrieval_engine_index_search_batch(
    'idx_h',
    ARRAY['[1,0,0,0]'::vector, '[4,0,0,0]'::vector]::vector[],
    2,
    '{}'::jsonb
);

SELECT count(*) AS filtered_batch_rows
FROM pg_retrieval_engine_index_search_batch_filtered(
    'idx_h',
    ARRAY['[1,0,0,0]'::vector, '[4,0,0,0]'::vector]::vector[],
    2,
    ARRAY[1,4]::bigint[],
    '{"candidate_k":4,"batch_size":1}'::jsonb
);

SELECT (pg_retrieval_engine_index_autotune('idx_h', 'balanced', '{"target_recall":0.97}'::jsonb)
        -> 'preferred_batch_size' ->> 'new')::int > 0 AS autotune_ok;

SELECT (pg_retrieval_engine_index_stats('idx_h')->'runtime'->>'search_filtered_calls')::int >= 2 AS runtime_filtered_ok;

SELECT pg_retrieval_engine_metrics_reset('idx_h') IS NOT NULL AS metrics_reset_ok;
SELECT (pg_retrieval_engine_index_stats('idx_h')->'runtime'->>'search_query_total')::int AS search_query_total_after_reset;

SELECT pg_retrieval_engine_index_save('idx_h', '/tmp/pg_retrieval_engine_regress.idx') IS NOT NULL AS save_ok;
SELECT pg_retrieval_engine_index_drop('idx_h') IS NOT NULL AS drop_hnsw_ok;
SELECT pg_retrieval_engine_index_load('idx_h', '/tmp/pg_retrieval_engine_regress.idx', 'cpu') IS NOT NULL AS load_ok;

SELECT id
FROM pg_retrieval_engine_index_search('idx_h', '[1,0,0,0]'::vector, 1, '{}'::jsonb);

SELECT pg_retrieval_engine_index_create(
    'idx_ivf',
    4,
    'cosine',
    'ivfflat',
    '{"nlist":2,"nprobe":2}'::jsonb,
    'cpu'
) IS NOT NULL AS create_ivf_ok;

SELECT pg_retrieval_engine_index_train(
    'idx_ivf',
    ARRAY[
        '[1,0,0,0]'::vector,
        '[0,1,0,0]'::vector,
        '[0,0,1,0]'::vector,
        '[0,0,0,1]'::vector
    ]::vector[]
) IS NOT NULL AS train_ivf_ok;

SELECT pg_retrieval_engine_index_add(
    'idx_ivf',
    ARRAY[11,12,13,14]::bigint[],
    ARRAY[
        '[1,0,0,0]'::vector,
        '[0,1,0,0]'::vector,
        '[0,0,1,0]'::vector,
        '[0,0,0,1]'::vector
    ]::vector[]
) AS added_ivf;

SELECT id
FROM pg_retrieval_engine_index_search('idx_ivf', '[1,0,0,0]'::vector, 1, '{"nprobe":2}'::jsonb);

SELECT id, vector_rank, fts_rank, round(rrf_score::numeric, 6) AS rrf_score
FROM pg_retrieval_engine_rrf_fuse(
    ARRAY[1,2,3]::bigint[],
    ARRAY[3,2,4]::bigint[],
    4
);

CREATE TABLE rrf_docs (
    id bigint PRIMARY KEY,
    embedding vector(4),
    search_vector tsvector
);

INSERT INTO rrf_docs VALUES
    (1, '[1,0,0,0]'::vector, to_tsvector('simple', 'apple database vector')),
    (2, '[0.9,0.1,0,0]'::vector, to_tsvector('simple', 'apple search ranking')),
    (3, '[0,1,0,0]'::vector, to_tsvector('simple', 'banana text search')),
    (4, '[0,0,1,0]'::vector, to_tsvector('simple', 'apple apple full text'));

\pset format unaligned

SELECT pg_retrieval_engine_pgvector_index_create(
    'rrf_docs'::regclass,
    'embedding',
    'hnsw',
    'vector_l2_ops',
    '{"m":8,"ef_construction":16}'::jsonb
) LIKE '%embedding_hnsw_idx' AS pgvector_hnsw_index_ok;

SELECT pg_retrieval_engine_pgvector_index_create(
    'rrf_docs'::regclass,
    'embedding',
    'ivfflat',
    'vector_l2_ops',
    '{"lists":1}'::jsonb
) LIKE '%embedding_ivfflat_idx' AS pgvector_ivfflat_index_ok;

SELECT pg_retrieval_engine_tsvector_index_create(
    'rrf_docs'::regclass,
    'search_vector'
) LIKE '%search_vector_gin_idx' AS tsvector_index_ok;

\pset format aligned

SELECT id,
       vector_rank,
       fts_rank,
       vector_distance IS NOT NULL AS has_vector,
       fts_score IS NOT NULL AS has_fts
FROM pg_retrieval_engine_hybrid_search(
    'rrf_docs'::regclass,
    'id',
    'embedding',
    'search_vector',
    '[1,0,0,0]'::vector,
    to_tsquery('simple', 'apple'),
    3,
    '{"vector_k":2,"fts_k":2,"rrf_k":60,"rank_function":"ts_rank","normalization":0}'::jsonb
);

\pset format unaligned

SELECT count(*) AS faiss_hybrid_rows
FROM pg_retrieval_engine_hybrid_search_faiss(
    'rrf_docs'::regclass,
    'id',
    'search_vector',
    'idx_h',
    '[1,0,0,0]'::vector,
    to_tsquery('simple', 'apple'),
    3,
    '{"vector_k":3,"fts_k":3,"rrf_k":60,"rank_function":"ts_rank","normalization":0}'::jsonb
);

SELECT format('%s|%s|%s|%s', id, base_rank, round(final_score::numeric, 6), round(base_score::numeric, 6)) AS rerank_base
FROM pg_retrieval_engine_rerank(ARRAY[10,20,30]::bigint[], 2);

SELECT format('%s|%s|%s|%s', id, base_rank, round(final_score::numeric, 6), cross_encoder_score) AS rerank_cross_encoder
FROM pg_retrieval_engine_rerank(
    ARRAY[10,20,30]::bigint[],
    3,
    ARRAY[0.1,0.9,0.2]::double precision[],
    NULL,
    NULL,
    NULL,
    '{"base_weight":0,"cross_encoder_weight":1}'::jsonb
);

SELECT format('%s|%s|%s|%s', id, round(final_score::numeric, 6), llm_score, rule_score) AS rerank_llm_rule
FROM pg_retrieval_engine_rerank(
    ARRAY[1,2,3]::bigint[],
    3,
    NULL,
    ARRAY[0.4,0.1,0.7]::double precision[],
    ARRAY[1.0,0.0,0.2]::double precision[],
    ARRAY[0.0,0.0,0.0]::double precision[],
    '{"base_weight":0,"cross_encoder_weight":0,"llm_weight":2,"rule_weight":0.5}'::jsonb
);

SELECT format('%s|%s', id, round(final_score::numeric, 6)) AS rerank_minmax
FROM pg_retrieval_engine_rerank(
    ARRAY[1,2,3]::bigint[],
    3,
    ARRAY[5.0,10.0,15.0]::double precision[],
    NULL,
    NULL,
    ARRAY[10.0,20.0,30.0]::double precision[],
    '{"base_weight":1,"cross_encoder_weight":1,"llm_weight":0,"rule_weight":0,"score_normalization":"minmax"}'::jsonb
);

SELECT format('%s|%s|%s', id, base_rank, cross_encoder_score) AS rerank_dedup
FROM pg_retrieval_engine_rerank(
    ARRAY[5,6,5,7]::bigint[],
    4,
    ARRAY[0.1,0.2,0.9,0.3]::double precision[],
    NULL,
    NULL,
    NULL,
    '{"base_weight":0,"cross_encoder_weight":1}'::jsonb
);

SELECT format('%s|%s', id, citation->>'source_uri') AS rerank_citation
FROM pg_retrieval_engine_rerank_with_citations(
    ARRAY[10,20]::bigint[],
    ARRAY['{"source_uri":"file:///a.md"}'::jsonb, '{"source_uri":"file:///b.md"}'::jsonb],
    2,
    ARRAY[0.1,0.9]::double precision[],
    NULL,
    NULL,
    NULL,
    '{"base_weight":0,"cross_encoder_weight":1}'::jsonb
);

SELECT pg_retrieval_engine_retrieval_explain(
    ARRAY[1,2]::bigint[],
    ARRAY[2,3]::bigint[],
    ARRAY[2]::bigint[],
    ARRAY[1,2,4]::bigint[],
    '{}'::jsonb
)->>'likely_failure_reason' AS explain_reason;

SELECT pg_retrieval_engine_rerank(ARRAY[1]::bigint[], 0);
SELECT pg_retrieval_engine_rerank(ARRAY[1,2]::bigint[], 2, ARRAY[0.1]::double precision[]);
SELECT pg_retrieval_engine_rerank(ARRAY[1]::bigint[], 1, NULL, NULL, NULL, NULL, '{"base_weight":-1}'::jsonb);
SELECT pg_retrieval_engine_rerank(ARRAY[1]::bigint[], 1, NULL, NULL, NULL, NULL, '{"rank_k":0}'::jsonb);
SELECT pg_retrieval_engine_rerank(ARRAY[1]::bigint[], 1, NULL, NULL, NULL, NULL, '{"score_normalization":"zscore"}'::jsonb);
SELECT pg_retrieval_engine_document_upsert('', 'markdown', 'x');
SELECT pg_retrieval_engine_chunk_document(999999, 10, 0);
SELECT pg_retrieval_engine_pgvector_index_create('rrf_docs'::regclass, 'embedding', 'bad');

\pset format aligned

DROP TABLE rrf_docs;

SELECT pg_retrieval_engine_index_drop('idx_h') IS NOT NULL AS drop_loaded_ok;
SELECT pg_retrieval_engine_index_drop('idx_ivf') IS NOT NULL AS drop_ivf_ok;
SELECT pg_retrieval_engine_reset() IS NOT NULL AS final_reset_ok;
