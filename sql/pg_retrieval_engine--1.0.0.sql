-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_retrieval_engine" to load this file. \quit

CREATE FUNCTION pg_retrieval_engine_index_create(
    name text,
    dim integer,
    metric text,
    index_type text,
    options jsonb DEFAULT '{}'::jsonb,
    device text DEFAULT 'cpu'
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_create'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_train(
    name text,
    training_vectors vector[]
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_train'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_add(
    name text,
    ids bigint[],
    vectors vector[]
) RETURNS bigint
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_add'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_search(
    name text,
    query vector,
    k integer,
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_search'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_search_batch(
    name text,
    queries vector[],
    k integer,
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(query_no integer, id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_search_batch'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_search_filtered(
    name text,
    query vector,
    k integer,
    filter_ids bigint[],
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_search_filtered'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_search_batch_filtered(
    name text,
    queries vector[],
    k integer,
    filter_ids bigint[],
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(query_no integer, id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_search_batch_filtered'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_save(
    name text,
    path text
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_save'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_load(
    name text,
    path text,
    device text DEFAULT 'cpu'
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_load'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_autotune(
    name text,
    mode text DEFAULT 'balanced',
    options jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_autotune'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_metrics_reset(name text DEFAULT NULL)
RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_metrics_reset'
LANGUAGE C VOLATILE;

CREATE FUNCTION pg_retrieval_engine_index_stats(name text)
RETURNS jsonb
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_stats'
LANGUAGE C STABLE STRICT;

CREATE FUNCTION pg_retrieval_engine_index_drop(name text)
RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_index_drop'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_retrieval_engine_reset()
RETURNS void
AS 'MODULE_PATHNAME', 'pg_retrieval_engine_reset'
LANGUAGE C VOLATILE;

COMMENT ON FUNCTION pg_retrieval_engine_index_create(text, integer, text, text, jsonb, text)
IS 'Create a FAISS index. index_type: hnsw|ivfflat|ivfpq, metric: l2|ip|cosine, device: cpu|gpu.';

COMMENT ON FUNCTION pg_retrieval_engine_index_train(text, vector[])
IS 'Train IVF indexes using vector[] input.';

COMMENT ON FUNCTION pg_retrieval_engine_index_add(text, bigint[], vector[])
IS 'Bulk add vectors with explicit IDs.';

COMMENT ON FUNCTION pg_retrieval_engine_index_search(text, vector, integer, jsonb)
IS 'Search nearest neighbors and return (id, distance).';

COMMENT ON FUNCTION pg_retrieval_engine_index_search_batch(text, vector[], integer, jsonb)
IS 'Batch nearest-neighbor search and return (query_no, id, distance).';

COMMENT ON FUNCTION pg_retrieval_engine_index_search_filtered(text, vector, integer, bigint[], jsonb)
IS 'Hybrid retrieval: ANN search + ID prefilter list, return (id, distance).';

COMMENT ON FUNCTION pg_retrieval_engine_index_search_batch_filtered(text, vector[], integer, bigint[], jsonb)
IS 'Hybrid retrieval batch path: ANN search + ID prefilter list.';

COMMENT ON FUNCTION pg_retrieval_engine_index_save(text, text)
IS 'Persist index to disk. Metadata is stored at <path>.meta.';

COMMENT ON FUNCTION pg_retrieval_engine_index_load(text, text, text)
IS 'Load persisted index from disk.';

COMMENT ON FUNCTION pg_retrieval_engine_index_autotune(text, text, jsonb)
IS 'Auto tune search defaults (ef_search/nprobe/batch_size) for latency|balanced|recall targets.';

COMMENT ON FUNCTION pg_retrieval_engine_metrics_reset(text)
IS 'Reset runtime observability counters for one index or all indexes when name is NULL.';

COMMENT ON FUNCTION pg_retrieval_engine_index_stats(text)
IS 'Return index metadata and runtime statistics as jsonb.';

COMMENT ON FUNCTION pg_retrieval_engine_index_drop(text)
IS 'Drop one in-memory index.';

COMMENT ON FUNCTION pg_retrieval_engine_reset()
IS 'Drop all in-memory indexes in current backend process.';

CREATE TABLE pg_retrieval_engine_documents (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    source_uri text NOT NULL,
    source_type text NOT NULL CHECK (source_type IN (
        'technical_doc', 'log', 'sql', 'markdown', 'pdf', 'html', 'text'
    )),
    title text,
    content text NOT NULL,
    content_hash text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_documents_source_uri_uq UNIQUE (source_uri)
);

CREATE TABLE pg_retrieval_engine_embedding_versions (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    model_name text NOT NULL,
    model_version text NOT NULL,
    dimensions integer NOT NULL CHECK (dimensions > 0),
    distance_metric text NOT NULL DEFAULT 'cosine' CHECK (distance_metric IN ('l2', 'ip', 'cosine')),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_embedding_versions_model_uq UNIQUE (model_name, model_version)
);

CREATE TABLE pg_retrieval_engine_chunks (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    document_id bigint NOT NULL REFERENCES pg_retrieval_engine_documents(id) ON DELETE CASCADE,
    parent_chunk_id bigint REFERENCES pg_retrieval_engine_chunks(id) ON DELETE CASCADE,
    chunk_no integer NOT NULL,
    chunk_type text NOT NULL DEFAULT 'child' CHECK (chunk_type IN ('parent', 'child')),
    content text NOT NULL,
    token_start integer NOT NULL,
    token_end integer NOT NULL,
    content_hash text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    citation_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    search_vector tsvector NOT NULL,
    embedding vector,
    embedding_version_id bigint REFERENCES pg_retrieval_engine_embedding_versions(id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_id, chunk_type, chunk_no)
);

CREATE TABLE pg_retrieval_engine_embedding_jobs (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    chunk_id bigint NOT NULL REFERENCES pg_retrieval_engine_chunks(id) ON DELETE CASCADE,
    embedding_version_id bigint NOT NULL REFERENCES pg_retrieval_engine_embedding_versions(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'done', 'failed')),
    content_hash text NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_embedding_jobs_chunk_version_uq UNIQUE (chunk_id, embedding_version_id)
);

CREATE INDEX pg_retrieval_engine_chunks_document_idx
ON pg_retrieval_engine_chunks(document_id, chunk_type, chunk_no);

CREATE INDEX pg_retrieval_engine_chunks_search_vector_idx
ON pg_retrieval_engine_chunks USING gin(search_vector);

CREATE INDEX pg_retrieval_engine_chunks_metadata_idx
ON pg_retrieval_engine_chunks USING gin(metadata);

CREATE FUNCTION pg_retrieval_engine_document_upsert(
    source_uri text,
    source_type text,
    content text,
    metadata jsonb DEFAULT '{}'::jsonb,
    title text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    document_id bigint;
BEGIN
    IF source_uri IS NULL OR source_uri = '' THEN
        RAISE EXCEPTION 'source_uri must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF source_type NOT IN ('technical_doc', 'log', 'sql', 'markdown', 'pdf', 'html', 'text') THEN
        RAISE EXCEPTION 'source_type is not supported' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF content IS NULL THEN
        RAISE EXCEPTION 'content must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO pg_retrieval_engine_documents AS d
        (source_uri, source_type, title, content, content_hash, metadata)
    VALUES
        (source_uri, source_type, title, content, md5(content), COALESCE(metadata, '{}'::jsonb))
    ON CONFLICT ON CONSTRAINT pg_retrieval_engine_documents_source_uri_uq DO UPDATE
    SET source_type = EXCLUDED.source_type,
        title = EXCLUDED.title,
        content = EXCLUDED.content,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        updated_at = now()
    RETURNING d.id INTO document_id;

    RETURN document_id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_chunk_document(
    document_id bigint,
    chunk_size integer DEFAULT 1000,
    chunk_overlap integer DEFAULT 100,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    chunk_id bigint,
    parent_chunk_id bigint,
    chunk_no integer,
    chunk_type text,
    content text,
    citation_metadata jsonb
)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    doc record;
    search_config regconfig;
    parent_size integer;
    content_len integer;
    pos integer;
    chunk_text text;
    parent_text text;
    parent_id bigint;
    parent_end integer;
    child_no integer;
    parent_no integer;
    step_size integer;
    inserted_id bigint;
    citation jsonb;
BEGIN
    IF chunk_size < 1 THEN
        RAISE EXCEPTION 'chunk_size must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF chunk_overlap < 0 OR chunk_overlap >= chunk_size THEN
        RAISE EXCEPTION 'chunk_overlap must be >= 0 and < chunk_size'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO doc
    FROM pg_retrieval_engine_documents d
    WHERE d.id = document_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'document does not exist' USING ERRCODE = 'undefined_object';
    END IF;

    search_config := COALESCE((options->>'search_config')::regconfig, 'simple'::regconfig);
    parent_size := COALESCE((options->>'parent_chunk_size')::integer, 0);
    IF parent_size > 0 AND parent_size < chunk_size THEN
        RAISE EXCEPTION 'parent_chunk_size must be >= chunk_size'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    DELETE FROM pg_retrieval_engine_chunks c
    WHERE c.document_id = pg_retrieval_engine_chunk_document.document_id;

    content_len := char_length(doc.content);
    pos := 1;
    child_no := 0;
    parent_no := 0;
    parent_id := NULL;
    parent_end := 0;
    step_size := chunk_size - chunk_overlap;

    WHILE pos <= GREATEST(content_len, 1) LOOP
        IF parent_size > 0 AND (parent_id IS NULL OR pos > parent_end) THEN
            parent_no := parent_no + 1;
            parent_text := substring(doc.content FROM pos FOR parent_size);
            parent_end := LEAST(content_len, pos + parent_size - 1);
            citation := jsonb_build_object(
                'document_id', doc.id,
                'source_uri', doc.source_uri,
                'source_type', doc.source_type,
                'title', doc.title,
                'chunk_type', 'parent',
                'chunk_no', parent_no,
                'char_start', pos,
                'char_end', parent_end,
                'metadata', doc.metadata
            );

            INSERT INTO pg_retrieval_engine_chunks
                (document_id, parent_chunk_id, chunk_no, chunk_type, content, token_start,
                 token_end, content_hash, metadata, citation_metadata, search_vector)
            VALUES
                (doc.id, NULL, parent_no, 'parent', parent_text, pos, parent_end,
                 md5(parent_text), doc.metadata, citation, to_tsvector(search_config, parent_text))
            RETURNING id INTO parent_id;

            inserted_id := parent_id;
            chunk_id := inserted_id;
            parent_chunk_id := NULL;
            chunk_no := parent_no;
            chunk_type := 'parent';
            content := parent_text;
            citation_metadata := citation;
            RETURN NEXT;
        END IF;

        child_no := child_no + 1;
        chunk_text := substring(doc.content FROM pos FOR chunk_size);
        citation := jsonb_build_object(
            'document_id', doc.id,
            'source_uri', doc.source_uri,
            'source_type', doc.source_type,
            'title', doc.title,
            'chunk_type', 'child',
            'chunk_no', child_no,
            'parent_chunk_id', parent_id,
            'char_start', pos,
            'char_end', LEAST(content_len, pos + char_length(chunk_text) - 1),
            'metadata', doc.metadata
        );

        INSERT INTO pg_retrieval_engine_chunks
            (document_id, parent_chunk_id, chunk_no, chunk_type, content, token_start,
             token_end, content_hash, metadata, citation_metadata, search_vector)
        VALUES
            (doc.id, parent_id, child_no, 'child', chunk_text, pos,
             LEAST(content_len, pos + char_length(chunk_text) - 1), md5(chunk_text),
             doc.metadata, citation, to_tsvector(search_config, chunk_text))
        RETURNING id INTO inserted_id;

        chunk_id := inserted_id;
        parent_chunk_id := parent_id;
        chunk_no := child_no;
        chunk_type := 'child';
        content := chunk_text;
        citation_metadata := citation;
        RETURN NEXT;

        EXIT WHEN pos + step_size > content_len;
        pos := pos + step_size;
    END LOOP;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_embedding_version_create(
    model_name text,
    model_version text,
    dimensions integer,
    distance_metric text DEFAULT 'cosine',
    metadata jsonb DEFAULT '{}'::jsonb,
    is_active boolean DEFAULT true
) RETURNS bigint
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    version_id bigint;
BEGIN
    IF model_name IS NULL OR model_name = '' THEN
        RAISE EXCEPTION 'model_name must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF model_version IS NULL OR model_version = '' THEN
        RAISE EXCEPTION 'model_version must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF dimensions < 1 THEN
        RAISE EXCEPTION 'dimensions must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF distance_metric NOT IN ('l2', 'ip', 'cosine') THEN
        RAISE EXCEPTION 'distance_metric must be l2, ip, or cosine'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO pg_retrieval_engine_embedding_versions AS v
        (model_name, model_version, dimensions, distance_metric, metadata, is_active)
    VALUES
        (model_name, model_version, dimensions, distance_metric, COALESCE(metadata, '{}'::jsonb), is_active)
    ON CONFLICT ON CONSTRAINT pg_retrieval_engine_embedding_versions_model_uq DO UPDATE
    SET dimensions = EXCLUDED.dimensions,
        distance_metric = EXCLUDED.distance_metric,
        metadata = EXCLUDED.metadata,
        is_active = EXCLUDED.is_active
    RETURNING v.id INTO version_id;

    RETURN version_id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_enqueue_embedding_jobs(
    embedding_version_id bigint,
    only_changed boolean DEFAULT true
) RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    inserted_count integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_retrieval_engine_embedding_versions v
        WHERE v.id = embedding_version_id
    ) THEN
        RAISE EXCEPTION 'embedding version does not exist' USING ERRCODE = 'undefined_object';
    END IF;

    WITH upserted AS (
        INSERT INTO pg_retrieval_engine_embedding_jobs
            (chunk_id, embedding_version_id, status, content_hash, attempts, metadata)
        SELECT c.id, pg_retrieval_engine_enqueue_embedding_jobs.embedding_version_id,
               'pending', c.content_hash, 0, '{}'::jsonb
        FROM pg_retrieval_engine_chunks c
        WHERE c.chunk_type = 'child'
          AND (
              NOT only_changed
              OR c.embedding IS NULL
              OR c.embedding_version_id IS DISTINCT FROM pg_retrieval_engine_enqueue_embedding_jobs.embedding_version_id
              OR NOT EXISTS (
                  SELECT 1
                  FROM pg_retrieval_engine_embedding_jobs existing
                  WHERE existing.chunk_id = c.id
                    AND existing.embedding_version_id = pg_retrieval_engine_enqueue_embedding_jobs.embedding_version_id
                    AND existing.content_hash = c.content_hash
                    AND existing.status = 'done'
              )
          )
        ON CONFLICT ON CONSTRAINT pg_retrieval_engine_embedding_jobs_chunk_version_uq DO UPDATE
        SET status = CASE
                WHEN pg_retrieval_engine_embedding_jobs.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                     OR NOT only_changed
                    THEN 'pending'
                ELSE pg_retrieval_engine_embedding_jobs.status
            END,
            content_hash = EXCLUDED.content_hash,
            updated_at = now()
        RETURNING 1
    )
    SELECT count(*)::integer INTO inserted_count FROM upserted;

    RETURN inserted_count;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_embedding_job_complete(
    job_id bigint,
    embedding vector,
    metadata jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    job record;
BEGIN
    SELECT * INTO job
    FROM pg_retrieval_engine_embedding_jobs j
    WHERE j.id = job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'embedding job does not exist' USING ERRCODE = 'undefined_object';
    END IF;
    IF embedding IS NULL THEN
        RAISE EXCEPTION 'embedding must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    UPDATE pg_retrieval_engine_chunks c
    SET embedding = pg_retrieval_engine_embedding_job_complete.embedding,
        embedding_version_id = job.embedding_version_id,
        updated_at = now()
    WHERE c.id = job.chunk_id;

    UPDATE pg_retrieval_engine_embedding_jobs j
    SET status = 'done',
        metadata = COALESCE(pg_retrieval_engine_embedding_job_complete.metadata, '{}'::jsonb),
        updated_at = now()
    WHERE j.id = job_id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_pgvector_index_create(
    table_name regclass,
    vector_column name,
    index_type text,
    opclass text DEFAULT 'vector_cosine_ops',
    options jsonb DEFAULT '{}'::jsonb
) RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    index_name text;
    with_clause text;
BEGIN
    IF index_type NOT IN ('hnsw', 'ivfflat') THEN
        RAISE EXCEPTION 'index_type must be hnsw or ivfflat' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF opclass NOT IN ('vector_l2_ops', 'vector_ip_ops', 'vector_cosine_ops') THEN
        RAISE EXCEPTION 'opclass must be vector_l2_ops, vector_ip_ops, or vector_cosine_ops'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    index_name := format('%s_%s_%s_idx', replace(table_name::text, '.', '_'), vector_column, index_type);
    IF index_type = 'hnsw' THEN
        with_clause := format(
            'WITH (m = %s, ef_construction = %s)',
            COALESCE((options->>'m')::integer, 16),
            COALESCE((options->>'ef_construction')::integer, 64)
        );
    ELSE
        with_clause := format('WITH (lists = %s)', COALESCE((options->>'lists')::integer, 100));
    END IF;

    EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON %s USING %s (%I %s) %s',
        index_name, table_name, index_type, vector_column, opclass, with_clause
    );

    RETURN index_name;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_tsvector_index_create(
    table_name regclass,
    tsvector_column name
) RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    index_name text;
BEGIN
    index_name := format('%s_%s_gin_idx', replace(table_name::text, '.', '_'), tsvector_column);
    EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON %s USING gin (%I)',
        index_name, table_name, tsvector_column
    );
    RETURN index_name;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_rrf_fuse(
    vector_ids bigint[],
    fts_ids bigint[],
    k integer,
    rrf_k double precision DEFAULT 60.0,
    vector_weight double precision DEFAULT 1.0,
    fts_weight double precision DEFAULT 1.0
) RETURNS TABLE(
    id bigint,
    rrf_score double precision,
    vector_rank integer,
    fts_rank integer
)
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
BEGIN
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rrf_k <= 0 THEN
        RAISE EXCEPTION 'rrf_k must be > 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF vector_weight < 0 THEN
        RAISE EXCEPTION 'vector_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF fts_weight < 0 THEN
        RAISE EXCEPTION 'fts_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY
    WITH params AS (
        SELECT
            k AS limit_k,
            rrf_k AS rrf_k,
            vector_weight AS vector_weight,
            fts_weight AS fts_weight
    ),
    vector_ranked AS (
        SELECT ranked.id, min(ranked.ord)::integer AS rank
        FROM unnest(vector_ids) WITH ORDINALITY AS ranked(id, ord)
        GROUP BY ranked.id
    ),
    fts_ranked AS (
        SELECT ranked.id, min(ranked.ord)::integer AS rank
        FROM unnest(fts_ids) WITH ORDINALITY AS ranked(id, ord)
        GROUP BY ranked.id
    ),
    fused AS (
        SELECT
            COALESCE(v.id, f.id) AS id,
            v.rank AS vector_rank,
            f.rank AS fts_rank,
            CASE WHEN v.rank IS NULL THEN 0.0
                 ELSE p.vector_weight / (p.rrf_k + v.rank::double precision)
            END
            +
            CASE WHEN f.rank IS NULL THEN 0.0
                 ELSE p.fts_weight / (p.rrf_k + f.rank::double precision)
            END AS rrf_score
        FROM vector_ranked v
        FULL OUTER JOIN fts_ranked f USING (id)
        CROSS JOIN params p
    )
    SELECT fused.id, fused.rrf_score, fused.vector_rank, fused.fts_rank
    FROM fused
    ORDER BY fused.rrf_score DESC, LEAST(COALESCE(fused.vector_rank, 2147483647),
                                         COALESCE(fused.fts_rank, 2147483647)), fused.id
    LIMIT (SELECT params.limit_k FROM params);
END;
$$;

CREATE FUNCTION pg_retrieval_engine_hybrid_search(
    table_name regclass,
    id_column name,
    vector_column name,
    tsvector_column name,
    query_vector vector,
    query_tsquery tsquery,
    k integer,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    id bigint,
    rrf_score double precision,
    vector_rank integer,
    fts_rank integer,
    vector_distance real,
    fts_score real
)
LANGUAGE plpgsql
STABLE
STRICT
AS $$
DECLARE
    vector_k integer;
    fts_k integer;
    rrf_k double precision;
    vector_weight double precision;
    fts_weight double precision;
    vector_operator text;
    rank_function text;
    normalization integer;
BEGIN
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    vector_k := COALESCE((options->>'vector_k')::integer,
                         (options->>'dense_k')::integer,
                         GREATEST(k * 4, k));
    fts_k := COALESCE((options->>'fts_k')::integer,
                      (options->>'sparse_k')::integer,
                      GREATEST(k * 4, k));
    rrf_k := COALESCE((options->>'rrf_k')::double precision, 60.0);
    vector_weight := COALESCE((options->>'vector_weight')::double precision,
                              (options->>'dense_weight')::double precision,
                              1.0);
    fts_weight := COALESCE((options->>'fts_weight')::double precision,
                           (options->>'sparse_weight')::double precision,
                           1.0);
    vector_operator := COALESCE(options->>'vector_operator', '<=>');
    rank_function := COALESCE(options->>'rank_function', 'ts_rank_cd');
    normalization := COALESCE((options->>'normalization')::integer, 32);

    IF vector_k < 1 THEN
        RAISE EXCEPTION 'vector_k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF fts_k < 1 THEN
        RAISE EXCEPTION 'fts_k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rrf_k <= 0 THEN
        RAISE EXCEPTION 'rrf_k must be > 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF vector_weight < 0 THEN
        RAISE EXCEPTION 'vector_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF fts_weight < 0 THEN
        RAISE EXCEPTION 'fts_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF vector_operator NOT IN ('<->', '<#>', '<=>') THEN
        RAISE EXCEPTION 'vector_operator must be one of <->, <#>, <=>'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rank_function NOT IN ('ts_rank', 'ts_rank_cd') THEN
        RAISE EXCEPTION 'rank_function must be ts_rank or ts_rank_cd'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF normalization < 0 OR normalization > 63 THEN
        RAISE EXCEPTION 'normalization must be in range 0..63'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY EXECUTE format($sql$
        WITH vector_results AS (
            SELECT
                %1$I::bigint AS id,
                (%2$I %8$s $1)::real AS vector_distance,
                row_number() OVER (ORDER BY %2$I %8$s $1, %1$I)::integer AS vector_rank
            FROM %3$s
            WHERE %2$I IS NOT NULL
            ORDER BY %2$I %8$s $1, %1$I
            LIMIT %4$s
        ),
        fts_results AS (
            SELECT
                %1$I::bigint AS id,
                pg_catalog.%9$s(%5$I, $2, %10$s)::real AS fts_score,
                row_number() OVER (ORDER BY pg_catalog.%9$s(%5$I, $2, %10$s) DESC, %1$I)::integer AS fts_rank
            FROM %3$s
            WHERE %5$I @@ $2
            ORDER BY pg_catalog.%9$s(%5$I, $2, %10$s) DESC, %1$I
            LIMIT %6$s
        ),
        fused AS (
            SELECT
                COALESCE(v.id, f.id) AS id,
                CASE WHEN v.vector_rank IS NULL THEN 0.0
                     ELSE $3::double precision / ($4::double precision + v.vector_rank::double precision)
                END
                +
                CASE WHEN f.fts_rank IS NULL THEN 0.0
                     ELSE $5::double precision / ($4::double precision + f.fts_rank::double precision)
                END AS rrf_score,
                v.vector_rank,
                f.fts_rank,
                v.vector_distance,
                f.fts_score
            FROM vector_results v
            FULL OUTER JOIN fts_results f USING (id)
        )
        SELECT id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score
        FROM fused
        ORDER BY rrf_score DESC,
                 LEAST(COALESCE(vector_rank, 2147483647),
                       COALESCE(fts_rank, 2147483647)),
                 id
        LIMIT %7$s
    $sql$,
        id_column,
        vector_column,
        table_name,
        vector_k,
        tsvector_column,
        fts_k,
        k,
        vector_operator,
        rank_function,
        normalization)
    USING query_vector, query_tsquery, vector_weight, rrf_k, fts_weight;
END;
$$;

COMMENT ON FUNCTION pg_retrieval_engine_rrf_fuse(bigint[], bigint[], integer, double precision, double precision, double precision)
IS 'Fuse vector and full-text ranked ID lists with Reciprocal Rank Fusion.';

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_search(regclass, name, name, name, vector, tsquery, integer, jsonb)
IS 'Run pgvector and PostgreSQL tsvector retrieval over one table, then merge rankings with Reciprocal Rank Fusion.';

CREATE FUNCTION pg_retrieval_engine_hybrid_search_faiss(
    table_name regclass,
    id_column name,
    tsvector_column name,
    faiss_index_name text,
    query_vector vector,
    query_tsquery tsquery,
    k integer,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    id bigint,
    rrf_score double precision,
    vector_rank integer,
    fts_rank integer,
    vector_distance real,
    fts_score real
)
LANGUAGE plpgsql
STABLE
STRICT
AS $$
DECLARE
    vector_k integer;
    fts_k integer;
    rrf_k double precision;
    vector_weight double precision;
    fts_weight double precision;
    rank_function text;
    normalization integer;
    search_params jsonb;
BEGIN
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    vector_k := COALESCE((options->>'vector_k')::integer,
                         (options->>'dense_k')::integer,
                         GREATEST(k * 4, k));
    fts_k := COALESCE((options->>'fts_k')::integer,
                      (options->>'sparse_k')::integer,
                      GREATEST(k * 4, k));
    rrf_k := COALESCE((options->>'rrf_k')::double precision, 60.0);
    vector_weight := COALESCE((options->>'vector_weight')::double precision,
                              (options->>'dense_weight')::double precision,
                              1.0);
    fts_weight := COALESCE((options->>'fts_weight')::double precision,
                           (options->>'sparse_weight')::double precision,
                           1.0);
    rank_function := COALESCE(options->>'rank_function', 'ts_rank_cd');
    normalization := COALESCE((options->>'normalization')::integer, 32);
    search_params := COALESCE(options->'faiss_search_params', '{}'::jsonb);

    IF vector_k < 1 THEN
        RAISE EXCEPTION 'vector_k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF fts_k < 1 THEN
        RAISE EXCEPTION 'fts_k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rrf_k <= 0 THEN
        RAISE EXCEPTION 'rrf_k must be > 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF vector_weight < 0 THEN
        RAISE EXCEPTION 'vector_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF fts_weight < 0 THEN
        RAISE EXCEPTION 'fts_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rank_function NOT IN ('ts_rank', 'ts_rank_cd') THEN
        RAISE EXCEPTION 'rank_function must be ts_rank or ts_rank_cd'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF normalization < 0 OR normalization > 63 THEN
        RAISE EXCEPTION 'normalization must be in range 0..63'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY EXECUTE format($sql$
        WITH vector_results AS (
            SELECT
                s.id,
                s.distance AS vector_distance,
                row_number() OVER (ORDER BY s.distance, s.id)::integer AS vector_rank
            FROM pg_retrieval_engine_index_search($1, $2, %4$s, $3) AS s
        ),
        fts_results AS (
            SELECT
                %1$I::bigint AS id,
                pg_catalog.%8$s(%2$I, $4, %9$s)::real AS fts_score,
                row_number() OVER (ORDER BY pg_catalog.%8$s(%2$I, $4, %9$s) DESC, %1$I)::integer AS fts_rank
            FROM %3$s
            WHERE %2$I @@ $4
            ORDER BY pg_catalog.%8$s(%2$I, $4, %9$s) DESC, %1$I
            LIMIT %5$s
        ),
        fused AS (
            SELECT
                COALESCE(v.id, f.id) AS id,
                CASE WHEN v.vector_rank IS NULL THEN 0.0
                     ELSE $5::double precision / ($6::double precision + v.vector_rank::double precision)
                END
                +
                CASE WHEN f.fts_rank IS NULL THEN 0.0
                     ELSE $7::double precision / ($6::double precision + f.fts_rank::double precision)
                END AS rrf_score,
                v.vector_rank,
                f.fts_rank,
                v.vector_distance,
                f.fts_score
            FROM vector_results v
            FULL OUTER JOIN fts_results f USING (id)
        )
        SELECT id, rrf_score, vector_rank, fts_rank, vector_distance, fts_score
        FROM fused
        ORDER BY rrf_score DESC,
                 LEAST(COALESCE(vector_rank, 2147483647),
                       COALESCE(fts_rank, 2147483647)),
                 id
        LIMIT %6$s
    $sql$,
        id_column,
        tsvector_column,
        table_name,
        vector_k,
        fts_k,
        k,
        rrf_k,
        rank_function,
        normalization)
    USING faiss_index_name, query_vector, search_params, query_tsquery,
          vector_weight, rrf_k, fts_weight;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_rerank(
    candidate_ids bigint[],
    k integer,
    cross_encoder_scores double precision[] DEFAULT NULL,
    llm_scores double precision[] DEFAULT NULL,
    rule_scores double precision[] DEFAULT NULL,
    base_scores double precision[] DEFAULT NULL,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    id bigint,
    final_score double precision,
    base_rank integer,
    base_score double precision,
    cross_encoder_score double precision,
    llm_score double precision,
    rule_score double precision,
    diagnostics jsonb
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    candidate_count integer;
    base_weight double precision;
    cross_encoder_weight double precision;
    llm_weight double precision;
    rule_weight double precision;
    rank_k double precision;
    score_normalization text;
BEGIN
    IF candidate_ids IS NULL THEN
        RAISE EXCEPTION 'candidate_ids must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    candidate_count := cardinality(candidate_ids);

    IF cross_encoder_scores IS NOT NULL AND cardinality(cross_encoder_scores) <> candidate_count THEN
        RAISE EXCEPTION 'cross_encoder_scores length must match candidate_ids length'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF llm_scores IS NOT NULL AND cardinality(llm_scores) <> candidate_count THEN
        RAISE EXCEPTION 'llm_scores length must match candidate_ids length'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rule_scores IS NOT NULL AND cardinality(rule_scores) <> candidate_count THEN
        RAISE EXCEPTION 'rule_scores length must match candidate_ids length'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF base_scores IS NOT NULL AND cardinality(base_scores) <> candidate_count THEN
        RAISE EXCEPTION 'base_scores length must match candidate_ids length'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    base_weight := COALESCE((options->>'base_weight')::double precision, 1.0);
    cross_encoder_weight := COALESCE((options->>'cross_encoder_weight')::double precision, 1.0);
    llm_weight := COALESCE((options->>'llm_weight')::double precision, 1.0);
    rule_weight := COALESCE((options->>'rule_weight')::double precision, 1.0);
    rank_k := COALESCE((options->>'rank_k')::double precision, 60.0);
    score_normalization := COALESCE(options->>'score_normalization', 'none');

    IF base_weight < 0 THEN
        RAISE EXCEPTION 'base_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF cross_encoder_weight < 0 THEN
        RAISE EXCEPTION 'cross_encoder_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF llm_weight < 0 THEN
        RAISE EXCEPTION 'llm_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rule_weight < 0 THEN
        RAISE EXCEPTION 'rule_weight must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF rank_k <= 0 THEN
        RAISE EXCEPTION 'rank_k must be > 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF score_normalization NOT IN ('none', 'minmax') THEN
        RAISE EXCEPTION 'score_normalization must be none or minmax'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY
    WITH raw_candidates AS (
        SELECT
            ids.id,
            ids.ord::integer AS base_rank,
            CASE WHEN base_scores IS NULL
                 THEN 1.0 / (rank_k + ids.ord::double precision)
                 ELSE base_scores[ids.ord]
            END AS base_score,
            CASE WHEN cross_encoder_scores IS NULL THEN NULL ELSE cross_encoder_scores[ids.ord] END AS cross_encoder_score,
            CASE WHEN llm_scores IS NULL THEN NULL ELSE llm_scores[ids.ord] END AS llm_score,
            CASE WHEN rule_scores IS NULL THEN NULL ELSE rule_scores[ids.ord] END AS rule_score
        FROM unnest(candidate_ids) WITH ORDINALITY AS ids(id, ord)
    ),
    candidates AS (
        SELECT DISTINCT ON (raw_candidates.id)
            raw_candidates.id,
            raw_candidates.base_rank,
            raw_candidates.base_score,
            raw_candidates.cross_encoder_score,
            raw_candidates.llm_score,
            raw_candidates.rule_score
        FROM raw_candidates
        ORDER BY raw_candidates.id, raw_candidates.base_rank
    ),
    stats AS (
        SELECT
            min(candidates.base_score) AS base_min,
            max(candidates.base_score) AS base_max,
            min(candidates.cross_encoder_score) AS cross_encoder_min,
            max(candidates.cross_encoder_score) AS cross_encoder_max,
            min(candidates.llm_score) AS llm_min,
            max(candidates.llm_score) AS llm_max,
            min(candidates.rule_score) AS rule_min,
            max(candidates.rule_score) AS rule_max
        FROM candidates
    ),
    normalized AS (
        SELECT
            c.id,
            c.base_rank,
            c.base_score,
            c.cross_encoder_score,
            c.llm_score,
            c.rule_score,
            CASE
                WHEN score_normalization = 'minmax' AND s.base_max > s.base_min
                    THEN (c.base_score - s.base_min) / (s.base_max - s.base_min)
                WHEN score_normalization = 'minmax'
                    THEN 0.0
                ELSE c.base_score
            END AS base_component,
            CASE
                WHEN score_normalization = 'minmax' AND s.cross_encoder_max > s.cross_encoder_min
                    THEN (c.cross_encoder_score - s.cross_encoder_min) / (s.cross_encoder_max - s.cross_encoder_min)
                WHEN score_normalization = 'minmax' AND c.cross_encoder_score IS NOT NULL
                    THEN 0.0
                ELSE c.cross_encoder_score
            END AS cross_encoder_component,
            CASE
                WHEN score_normalization = 'minmax' AND s.llm_max > s.llm_min
                    THEN (c.llm_score - s.llm_min) / (s.llm_max - s.llm_min)
                WHEN score_normalization = 'minmax' AND c.llm_score IS NOT NULL
                    THEN 0.0
                ELSE c.llm_score
            END AS llm_component,
            CASE
                WHEN score_normalization = 'minmax' AND s.rule_max > s.rule_min
                    THEN (c.rule_score - s.rule_min) / (s.rule_max - s.rule_min)
                WHEN score_normalization = 'minmax' AND c.rule_score IS NOT NULL
                    THEN 0.0
                ELSE c.rule_score
            END AS rule_component
        FROM candidates c
        CROSS JOIN stats s
    ),
    scored AS (
        SELECT
            n.id,
            (
                base_weight * COALESCE(n.base_component, 0.0) +
                cross_encoder_weight * COALESCE(n.cross_encoder_component, 0.0) +
                llm_weight * COALESCE(n.llm_component, 0.0) +
                rule_weight * COALESCE(n.rule_component, 0.0)
            ) AS final_score,
            n.base_rank,
            n.base_score,
            n.cross_encoder_score,
            n.llm_score,
            n.rule_score,
            jsonb_build_object(
                'score_normalization', score_normalization,
                'rank_k', rank_k,
                'weights', jsonb_build_object(
                    'base', base_weight,
                    'cross_encoder', cross_encoder_weight,
                    'llm', llm_weight,
                    'rule', rule_weight
                ),
                'components', jsonb_build_object(
                    'base', n.base_component,
                    'cross_encoder', n.cross_encoder_component,
                    'llm', n.llm_component,
                    'rule', n.rule_component
                )
            ) AS diagnostics
        FROM normalized n
    )
    SELECT
        scored.id,
        scored.final_score,
        scored.base_rank,
        scored.base_score,
        scored.cross_encoder_score,
        scored.llm_score,
        scored.rule_score,
        scored.diagnostics
    FROM scored
    ORDER BY scored.final_score DESC, scored.base_rank, scored.id
    LIMIT k;
END;
$$;

COMMENT ON FUNCTION pg_retrieval_engine_rerank(bigint[], integer, double precision[], double precision[], double precision[], double precision[], jsonb)
IS 'Rerank candidate IDs with externally supplied cross-encoder, LLM, rule-based, and base scores.';

CREATE FUNCTION pg_retrieval_engine_rerank_with_citations(
    candidate_ids bigint[],
    citation_metadata jsonb[],
    k integer,
    cross_encoder_scores double precision[] DEFAULT NULL,
    llm_scores double precision[] DEFAULT NULL,
    rule_scores double precision[] DEFAULT NULL,
    base_scores double precision[] DEFAULT NULL,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    id bigint,
    final_score double precision,
    base_rank integer,
    base_score double precision,
    cross_encoder_score double precision,
    llm_score double precision,
    rule_score double precision,
    citation jsonb,
    diagnostics jsonb
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    candidate_count integer;
BEGIN
    IF candidate_ids IS NULL THEN
        RAISE EXCEPTION 'candidate_ids must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    candidate_count := cardinality(candidate_ids);

    IF citation_metadata IS NOT NULL AND cardinality(citation_metadata) <> candidate_count THEN
        RAISE EXCEPTION 'citation_metadata length must match candidate_ids length'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY
    SELECT
        r.id,
        r.final_score,
        r.base_rank,
        r.base_score,
        r.cross_encoder_score,
        r.llm_score,
        r.rule_score,
        CASE WHEN citation_metadata IS NULL THEN '{}'::jsonb
             ELSE COALESCE(citation_metadata[r.base_rank], '{}'::jsonb)
        END AS citation,
        r.diagnostics
    FROM pg_retrieval_engine_rerank(
        candidate_ids,
        k,
        cross_encoder_scores,
        llm_scores,
        rule_scores,
        base_scores,
        options
    ) AS r;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_retrieval_explain(
    vector_ids bigint[] DEFAULT ARRAY[]::bigint[],
    fts_ids bigint[] DEFAULT ARRAY[]::bigint[],
    final_ids bigint[] DEFAULT ARRAY[]::bigint[],
    relevant_ids bigint[] DEFAULT NULL,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    vector_count integer;
    fts_count integer;
    final_count integer;
    overlap_count integer;
    vector_only_count integer;
    fts_only_count integer;
    missing_relevant bigint[];
    recalled_relevant bigint[];
    reason text;
BEGIN
    vector_ids := COALESCE(vector_ids, ARRAY[]::bigint[]);
    fts_ids := COALESCE(fts_ids, ARRAY[]::bigint[]);
    final_ids := COALESCE(final_ids, ARRAY[]::bigint[]);

    SELECT count(DISTINCT id)::integer INTO vector_count
    FROM unnest(vector_ids) AS ids(id);

    SELECT count(DISTINCT id)::integer INTO fts_count
    FROM unnest(fts_ids) AS ids(id);

    SELECT count(DISTINCT id)::integer INTO final_count
    FROM unnest(final_ids) AS ids(id);

    SELECT count(*)::integer INTO overlap_count
    FROM (
        SELECT DISTINCT id FROM unnest(vector_ids) AS v(id)
        INTERSECT
        SELECT DISTINCT id FROM unnest(fts_ids) AS f(id)
    ) overlap_ids;

    SELECT count(*)::integer INTO vector_only_count
    FROM (
        SELECT DISTINCT id FROM unnest(vector_ids) AS v(id)
        EXCEPT
        SELECT DISTINCT id FROM unnest(fts_ids) AS f(id)
    ) vector_only_ids;

    SELECT count(*)::integer INTO fts_only_count
    FROM (
        SELECT DISTINCT id FROM unnest(fts_ids) AS f(id)
        EXCEPT
        SELECT DISTINCT id FROM unnest(vector_ids) AS v(id)
    ) fts_only_ids;

    IF relevant_ids IS NULL THEN
        missing_relevant := NULL;
        recalled_relevant := NULL;
        reason := CASE WHEN final_count = 0 THEN 'no_final_results' ELSE 'no_relevance_labels' END;
    ELSE
        SELECT COALESCE(array_agg(r.id ORDER BY r.id), ARRAY[]::bigint[])
        INTO recalled_relevant
        FROM unnest(relevant_ids) AS r(id)
        WHERE r.id = ANY(final_ids);

        SELECT COALESCE(array_agg(r.id ORDER BY r.id), ARRAY[]::bigint[])
        INTO missing_relevant
        FROM unnest(relevant_ids) AS r(id)
        WHERE NOT r.id = ANY(final_ids);

        IF cardinality(missing_relevant) = 0 THEN
            reason := 'fully_recalled';
        ELSIF EXISTS (
            SELECT 1
            FROM unnest(missing_relevant) AS m(id)
            WHERE m.id = ANY(vector_ids) OR m.id = ANY(fts_ids)
        ) THEN
            reason := 'fusion_or_rerank_drop';
        ELSE
            reason := 'candidate_generation_miss';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'stage_counts', jsonb_build_object(
            'vector', vector_count,
            'fts', fts_count,
            'final', final_count,
            'overlap', overlap_count,
            'vector_only', vector_only_count,
            'fts_only', fts_only_count
        ),
        'relevance', jsonb_build_object(
            'recalled', recalled_relevant,
            'missing', missing_relevant
        ),
        'likely_failure_reason', reason,
        'options', COALESCE(options, '{}'::jsonb)
    );
END;
$$;

COMMENT ON FUNCTION pg_retrieval_engine_document_upsert(text, text, text, jsonb, text)
IS 'Register or update extracted source text for supported document types.';

COMMENT ON FUNCTION pg_retrieval_engine_chunk_document(bigint, integer, integer, jsonb)
IS 'Create structured child chunks and optional parent chunks with metadata and citation metadata.';

COMMENT ON FUNCTION pg_retrieval_engine_embedding_version_create(text, text, integer, text, jsonb, boolean)
IS 'Create or update an embedding model/version record.';

COMMENT ON FUNCTION pg_retrieval_engine_enqueue_embedding_jobs(bigint, boolean)
IS 'Queue child chunks that need embedding for a model version.';

COMMENT ON FUNCTION pg_retrieval_engine_embedding_job_complete(bigint, vector, jsonb)
IS 'Mark one embedding job complete and attach the produced vector to its chunk.';

COMMENT ON FUNCTION pg_retrieval_engine_pgvector_index_create(regclass, name, text, text, jsonb)
IS 'Create a pgvector HNSW or IVFFlat index for a vector column.';

COMMENT ON FUNCTION pg_retrieval_engine_tsvector_index_create(regclass, name)
IS 'Create a GIN index for a tsvector column.';

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_search_faiss(regclass, name, name, text, vector, tsquery, integer, jsonb)
IS 'Run FAISS dense retrieval and PostgreSQL tsvector retrieval, then fuse with RRF.';

COMMENT ON FUNCTION pg_retrieval_engine_rerank_with_citations(bigint[], jsonb[], integer, double precision[], double precision[], double precision[], double precision[], jsonb)
IS 'Rerank candidate IDs and attach citation metadata aligned to the input candidate order.';

COMMENT ON FUNCTION pg_retrieval_engine_retrieval_explain(bigint[], bigint[], bigint[], bigint[], jsonb)
IS 'Summarize retrieval stage counts and likely recall failure reasons.';
