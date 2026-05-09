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
    tenant_id text NOT NULL DEFAULT 'default',
    source_uri text NOT NULL,
    source_type text NOT NULL CHECK (source_type IN (
        'technical_doc', 'log', 'sql', 'markdown', 'pdf', 'html', 'text'
    )),
    title text,
    content text NOT NULL,
    content_hash text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    acl jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_documents_source_uri_uq UNIQUE (tenant_id, source_uri)
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
    tenant_id text NOT NULL DEFAULT 'default',
    chunk_no integer NOT NULL,
    chunk_type text NOT NULL DEFAULT 'child' CHECK (chunk_type IN ('parent', 'child')),
    content text NOT NULL,
    token_start integer NOT NULL,
    token_end integer NOT NULL,
    content_hash text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    acl jsonb NOT NULL DEFAULT '{}'::jsonb,
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
    locked_by text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_embedding_jobs_chunk_version_uq UNIQUE (chunk_id, embedding_version_id)
);

CREATE TABLE pg_retrieval_engine_chunk_embeddings (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    chunk_id bigint NOT NULL REFERENCES pg_retrieval_engine_chunks(id) ON DELETE CASCADE,
    embedding_version_id bigint NOT NULL REFERENCES pg_retrieval_engine_embedding_versions(id) ON DELETE CASCADE,
    embedding vector NOT NULL,
    content_hash text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pg_retrieval_engine_chunk_embeddings_chunk_version_uq UNIQUE (chunk_id, embedding_version_id)
);

CREATE INDEX pg_retrieval_engine_documents_tenant_idx
ON pg_retrieval_engine_documents(tenant_id, source_uri);

CREATE INDEX pg_retrieval_engine_chunks_document_idx
ON pg_retrieval_engine_chunks(document_id, chunk_type, chunk_no);

CREATE INDEX pg_retrieval_engine_chunks_tenant_idx
ON pg_retrieval_engine_chunks(tenant_id, chunk_type, id);

CREATE INDEX pg_retrieval_engine_chunks_search_vector_idx
ON pg_retrieval_engine_chunks USING gin(search_vector);

CREATE INDEX pg_retrieval_engine_chunks_metadata_idx
ON pg_retrieval_engine_chunks USING gin(metadata);

CREATE INDEX pg_retrieval_engine_chunks_acl_idx
ON pg_retrieval_engine_chunks USING gin(acl);

CREATE INDEX pg_retrieval_engine_chunk_embeddings_version_idx
ON pg_retrieval_engine_chunk_embeddings(embedding_version_id, chunk_id);

CREATE INDEX pg_retrieval_engine_embedding_jobs_claim_idx
ON pg_retrieval_engine_embedding_jobs(embedding_version_id, status, updated_at, id);

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
    opts jsonb;
    tenant_id text;
    acl jsonb;
BEGIN
    opts := COALESCE(metadata, '{}'::jsonb);
    IF jsonb_typeof(opts) <> 'object' THEN
        RAISE EXCEPTION 'metadata must be a JSON object' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    tenant_id := COALESCE(NULLIF(opts->>'tenant_id', ''), 'default');
    acl := COALESCE(opts->'acl', '{}'::jsonb);

    IF source_uri IS NULL OR source_uri = '' THEN
        RAISE EXCEPTION 'source_uri must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF tenant_id !~ '^[A-Za-z0-9_.:-]{1,128}$' THEN
        RAISE EXCEPTION 'tenant_id must match ^[A-Za-z0-9_.:-]{1,128}$'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF source_type NOT IN ('technical_doc', 'log', 'sql', 'markdown', 'pdf', 'html', 'text') THEN
        RAISE EXCEPTION 'source_type is not supported' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF content IS NULL THEN
        RAISE EXCEPTION 'content must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF jsonb_typeof(acl) IS NOT NULL AND jsonb_typeof(acl) <> 'object' THEN
        RAISE EXCEPTION 'metadata.acl must be a JSON object' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO pg_retrieval_engine_documents AS d
        (tenant_id, source_uri, source_type, title, content, content_hash, metadata, acl)
    VALUES
        (tenant_id, source_uri, source_type, title, content, md5(content), opts, acl)
    ON CONFLICT ON CONSTRAINT pg_retrieval_engine_documents_source_uri_uq DO UPDATE
    SET tenant_id = EXCLUDED.tenant_id,
        source_type = EXCLUDED.source_type,
        title = EXCLUDED.title,
        content = EXCLUDED.content,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        acl = EXCLUDED.acl,
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
    chunk_hash text;
    parent_ids bigint[] := ARRAY[]::bigint[];
    child_ids bigint[] := ARRAY[]::bigint[];
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
    WHERE d.id = document_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'document does not exist' USING ERRCODE = 'undefined_object';
    END IF;

    search_config := COALESCE((options->>'search_config')::regconfig, 'simple'::regconfig);
    parent_size := COALESCE((options->>'parent_chunk_size')::integer, 0);
    IF parent_size > 0 AND parent_size < chunk_size THEN
        RAISE EXCEPTION 'parent_chunk_size must be >= chunk_size'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

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
                'tenant_id', doc.tenant_id,
                'source_uri', doc.source_uri,
                'source_type', doc.source_type,
                'title', doc.title,
                'chunk_type', 'parent',
                'chunk_no', parent_no,
                'char_start', pos,
                'char_end', parent_end,
                'metadata', doc.metadata
            );
            chunk_hash := md5(parent_text);

            INSERT INTO pg_retrieval_engine_chunks
                (document_id, parent_chunk_id, tenant_id, chunk_no, chunk_type, content, token_start,
                 token_end, content_hash, metadata, acl, citation_metadata, search_vector)
            VALUES
                (doc.id, NULL, doc.tenant_id, parent_no, 'parent', parent_text, pos, parent_end,
                 chunk_hash, doc.metadata, doc.acl, citation, to_tsvector(search_config, parent_text))
            ON CONFLICT (document_id, chunk_type, chunk_no) DO UPDATE
            SET parent_chunk_id = EXCLUDED.parent_chunk_id,
                tenant_id = EXCLUDED.tenant_id,
                content = EXCLUDED.content,
                token_start = EXCLUDED.token_start,
                token_end = EXCLUDED.token_end,
                metadata = EXCLUDED.metadata,
                acl = EXCLUDED.acl,
                citation_metadata = EXCLUDED.citation_metadata,
                search_vector = EXCLUDED.search_vector,
                embedding = CASE
                    WHEN pg_retrieval_engine_chunks.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                        THEN NULL
                    ELSE pg_retrieval_engine_chunks.embedding
                END,
                embedding_version_id = CASE
                    WHEN pg_retrieval_engine_chunks.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                        THEN NULL
                    ELSE pg_retrieval_engine_chunks.embedding_version_id
                END,
                content_hash = EXCLUDED.content_hash,
                updated_at = now()
            RETURNING id INTO parent_id;
            parent_ids := parent_ids || parent_id;

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
            'tenant_id', doc.tenant_id,
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
        chunk_hash := md5(chunk_text);

        INSERT INTO pg_retrieval_engine_chunks
            (document_id, parent_chunk_id, tenant_id, chunk_no, chunk_type, content, token_start,
             token_end, content_hash, metadata, acl, citation_metadata, search_vector)
        VALUES
            (doc.id, parent_id, doc.tenant_id, child_no, 'child', chunk_text, pos,
             LEAST(content_len, pos + char_length(chunk_text) - 1), chunk_hash,
             doc.metadata, doc.acl, citation, to_tsvector(search_config, chunk_text))
        ON CONFLICT (document_id, chunk_type, chunk_no) DO UPDATE
        SET parent_chunk_id = EXCLUDED.parent_chunk_id,
            tenant_id = EXCLUDED.tenant_id,
            content = EXCLUDED.content,
            token_start = EXCLUDED.token_start,
            token_end = EXCLUDED.token_end,
            metadata = EXCLUDED.metadata,
            acl = EXCLUDED.acl,
            citation_metadata = EXCLUDED.citation_metadata,
            search_vector = EXCLUDED.search_vector,
            embedding = CASE
                WHEN pg_retrieval_engine_chunks.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                    THEN NULL
                ELSE pg_retrieval_engine_chunks.embedding
            END,
            embedding_version_id = CASE
                WHEN pg_retrieval_engine_chunks.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                    THEN NULL
                ELSE pg_retrieval_engine_chunks.embedding_version_id
            END,
            content_hash = EXCLUDED.content_hash,
            updated_at = now()
        RETURNING id INTO inserted_id;
        child_ids := child_ids || inserted_id;

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

    DELETE FROM pg_retrieval_engine_chunks c
    WHERE c.document_id = pg_retrieval_engine_chunk_document.document_id
      AND c.chunk_type = 'child'
      AND NOT (c.id = ANY(child_ids));

    DELETE FROM pg_retrieval_engine_chunks c
    WHERE c.document_id = pg_retrieval_engine_chunk_document.document_id
      AND c.chunk_type = 'parent'
      AND NOT (c.id = ANY(parent_ids));

    DELETE FROM pg_retrieval_engine_chunk_embeddings e
    USING pg_retrieval_engine_chunks c
    WHERE e.chunk_id = c.id
      AND c.document_id = pg_retrieval_engine_chunk_document.document_id
      AND e.content_hash IS DISTINCT FROM c.content_hash;
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
                  FROM pg_retrieval_engine_chunk_embeddings existing
                  WHERE existing.chunk_id = c.id
                    AND existing.embedding_version_id = pg_retrieval_engine_enqueue_embedding_jobs.embedding_version_id
                    AND existing.content_hash = c.content_hash
              )
          )
        ON CONFLICT ON CONSTRAINT pg_retrieval_engine_embedding_jobs_chunk_version_uq DO UPDATE
        SET status = CASE
                WHEN pg_retrieval_engine_embedding_jobs.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                     OR NOT only_changed
                    THEN 'pending'
                ELSE pg_retrieval_engine_embedding_jobs.status
            END,
            locked_by = CASE
                WHEN pg_retrieval_engine_embedding_jobs.content_hash IS DISTINCT FROM EXCLUDED.content_hash
                     OR NOT only_changed
                    THEN NULL
                ELSE pg_retrieval_engine_embedding_jobs.locked_by
            END,
            content_hash = EXCLUDED.content_hash,
            updated_at = now()
        RETURNING 1
    )
    SELECT count(*)::integer INTO inserted_count FROM upserted;

    RETURN inserted_count;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_claim_embedding_jobs(
    embedding_version_id bigint,
    batch_size integer DEFAULT 100,
    worker_id text DEFAULT NULL,
    lease_timeout_seconds integer DEFAULT 900,
    max_attempts integer DEFAULT 5
) RETURNS TABLE(
    job_id bigint,
    chunk_id bigint,
    content text,
    content_hash text,
    attempts integer,
    metadata jsonb
)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF batch_size < 1 THEN
        RAISE EXCEPTION 'batch_size must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF lease_timeout_seconds < 1 THEN
        RAISE EXCEPTION 'lease_timeout_seconds must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF max_attempts < 1 THEN
        RAISE EXCEPTION 'max_attempts must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_retrieval_engine_embedding_versions v
        WHERE v.id = embedding_version_id
    ) THEN
        RAISE EXCEPTION 'embedding version does not exist' USING ERRCODE = 'undefined_object';
    END IF;

    RETURN QUERY
    WITH picked AS (
        SELECT j.id,
               c.content_hash AS current_content_hash
        FROM pg_retrieval_engine_embedding_jobs j
        JOIN pg_retrieval_engine_chunks c ON c.id = j.chunk_id
        WHERE j.embedding_version_id = pg_retrieval_engine_claim_embedding_jobs.embedding_version_id
          AND j.attempts < max_attempts
          AND (
              j.status = 'pending'
              OR j.status = 'failed'
              OR (
                  j.status = 'running'
                  AND j.updated_at < now() - make_interval(secs => lease_timeout_seconds)
              )
          )
        ORDER BY j.id
        LIMIT batch_size
        FOR UPDATE OF j SKIP LOCKED
    ),
    claimed AS (
        UPDATE pg_retrieval_engine_embedding_jobs j
        SET status = 'running',
            attempts = j.attempts + 1,
            locked_by = worker_id,
            content_hash = picked.current_content_hash,
            metadata = j.metadata || jsonb_build_object(
                'worker_id', worker_id,
                'claimed_at', now()
            ) || CASE
                WHEN j.content_hash IS DISTINCT FROM picked.current_content_hash
                    THEN jsonb_build_object('stale_claim_refreshed_at', now())
                ELSE '{}'::jsonb
            END,
            updated_at = now()
        FROM picked
        WHERE j.id = picked.id
        RETURNING j.id, j.chunk_id, j.content_hash, j.attempts, j.metadata
    )
    SELECT claimed.id AS job_id,
           c.id AS chunk_id,
           c.content,
           claimed.content_hash,
           claimed.attempts,
           claimed.metadata
    FROM claimed
    JOIN pg_retrieval_engine_chunks c ON c.id = claimed.chunk_id
    ORDER BY claimed.id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_embedding_job_complete(
    job_id bigint,
    embedding vector,
    metadata jsonb DEFAULT '{}'::jsonb,
    expected_attempt integer DEFAULT NULL,
    worker_id text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    job record;
    version record;
    current_hash text;
BEGIN
    SELECT * INTO job
    FROM pg_retrieval_engine_embedding_jobs j
    WHERE j.id = job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'embedding job does not exist' USING ERRCODE = 'undefined_object';
    END IF;
    IF embedding IS NULL THEN
        RAISE EXCEPTION 'embedding must not be null' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF metadata IS NULL OR jsonb_typeof(metadata) <> 'object' THEN
        RAISE EXCEPTION 'metadata must be a JSON object' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF expected_attempt IS NOT NULL AND expected_attempt < 0 THEN
        RAISE EXCEPTION 'expected_attempt must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF job.status <> 'running' THEN
        RAISE EXCEPTION 'embedding job must be running, got %', job.status
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF expected_attempt IS NOT NULL AND job.attempts IS DISTINCT FROM expected_attempt THEN
        RAISE EXCEPTION 'embedding job attempt mismatch: expected %, got %',
            expected_attempt, job.attempts
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF worker_id IS NOT NULL AND job.locked_by IS DISTINCT FROM worker_id THEN
        RAISE EXCEPTION 'embedding job worker mismatch: expected %, got %',
            worker_id, job.locked_by
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    SELECT c.content_hash INTO current_hash
    FROM pg_retrieval_engine_chunks c
    WHERE c.id = job.chunk_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'embedding job chunk does not exist' USING ERRCODE = 'undefined_object';
    END IF;
    IF current_hash IS DISTINCT FROM job.content_hash THEN
        UPDATE pg_retrieval_engine_embedding_jobs j
        SET status = 'pending',
            content_hash = current_hash,
            locked_by = NULL,
            updated_at = now(),
            metadata = j.metadata || jsonb_build_object('stale_completion_rejected_at', now())
        WHERE j.id = job_id;

        RAISE EXCEPTION 'embedding job content hash is stale'
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    SELECT * INTO version
    FROM pg_retrieval_engine_embedding_versions v
    WHERE v.id = job.embedding_version_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'embedding version does not exist' USING ERRCODE = 'undefined_object';
    END IF;
    IF vector_dims(embedding) <> version.dimensions THEN
        RAISE EXCEPTION 'embedding dimension mismatch: expected %, got %',
            version.dimensions, vector_dims(embedding)
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    UPDATE pg_retrieval_engine_chunks c
    SET embedding = pg_retrieval_engine_embedding_job_complete.embedding,
        embedding_version_id = job.embedding_version_id,
        updated_at = now()
    WHERE c.id = job.chunk_id
      AND c.content_hash = job.content_hash;

    INSERT INTO pg_retrieval_engine_chunk_embeddings AS e
        (chunk_id, embedding_version_id, embedding, content_hash, metadata)
    VALUES
        (job.chunk_id, job.embedding_version_id, embedding, job.content_hash,
         COALESCE(pg_retrieval_engine_embedding_job_complete.metadata, '{}'::jsonb))
    ON CONFLICT ON CONSTRAINT pg_retrieval_engine_chunk_embeddings_chunk_version_uq DO UPDATE
    SET embedding = EXCLUDED.embedding,
        content_hash = EXCLUDED.content_hash,
        metadata = EXCLUDED.metadata,
        updated_at = now();

    UPDATE pg_retrieval_engine_embedding_jobs j
    SET status = 'done',
        locked_by = NULL,
        metadata = COALESCE(pg_retrieval_engine_embedding_job_complete.metadata, '{}'::jsonb),
        updated_at = now()
    WHERE j.id = job_id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_embedding_job_fail(
    job_id bigint,
    error_message text,
    metadata jsonb DEFAULT '{}'::jsonb,
    expected_attempt integer DEFAULT NULL,
    worker_id text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    job record;
BEGIN
    IF error_message IS NULL OR error_message = '' THEN
        RAISE EXCEPTION 'error_message must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF metadata IS NULL OR jsonb_typeof(metadata) <> 'object' THEN
        RAISE EXCEPTION 'metadata must be a JSON object' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF expected_attempt IS NOT NULL AND expected_attempt < 0 THEN
        RAISE EXCEPTION 'expected_attempt must be >= 0' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO job
    FROM pg_retrieval_engine_embedding_jobs j
    WHERE j.id = job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'embedding job does not exist' USING ERRCODE = 'undefined_object';
    END IF;
    IF job.status = 'done' THEN
        RAISE EXCEPTION 'embedding job is already done'
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF expected_attempt IS NOT NULL AND job.attempts IS DISTINCT FROM expected_attempt THEN
        RAISE EXCEPTION 'embedding job attempt mismatch: expected %, got %',
            expected_attempt, job.attempts
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;
    IF worker_id IS NOT NULL AND job.locked_by IS DISTINCT FROM worker_id THEN
        RAISE EXCEPTION 'embedding job worker mismatch: expected %, got %',
            worker_id, job.locked_by
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    UPDATE pg_retrieval_engine_embedding_jobs j
    SET status = 'failed',
        locked_by = NULL,
        metadata = j.metadata || metadata || jsonb_build_object(
            'last_error', error_message,
            'failed_at', now()
        ),
        updated_at = now()
    WHERE j.id = job_id;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_activate_embedding_version(
    embedding_version_id bigint,
    tenant_id text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    activated_count integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_retrieval_engine_embedding_versions v
        WHERE v.id = embedding_version_id
    ) THEN
        RAISE EXCEPTION 'embedding version does not exist' USING ERRCODE = 'undefined_object';
    END IF;

    UPDATE pg_retrieval_engine_chunks c
    SET embedding = e.embedding,
        embedding_version_id = e.embedding_version_id,
        updated_at = now()
    FROM pg_retrieval_engine_chunk_embeddings e
    WHERE e.chunk_id = c.id
      AND e.embedding_version_id = pg_retrieval_engine_activate_embedding_version.embedding_version_id
      AND e.content_hash = c.content_hash
      AND (pg_retrieval_engine_activate_embedding_version.tenant_id IS NULL
           OR c.tenant_id = pg_retrieval_engine_activate_embedding_version.tenant_id);

    GET DIAGNOSTICS activated_count = ROW_COUNT;
    RETURN activated_count;
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

CREATE FUNCTION pg_retrieval_engine_build_filter_clause(
    table_alias text,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    opts jsonb;
    metadata_filter jsonb;
    nested_metadata_filter jsonb;
    metadata_column name;
    acl_filter jsonb;
    nested_acl_filter jsonb;
    acl_column name;
    scalar_filters jsonb;
    filter_key text;
    filter_value jsonb;
    filter_op text;
    op_value jsonb;
    value_list text;
    soft_delete_column name;
    namespace_value text;
    agent_id_value text;
    user_id_value text;
    role_filters jsonb;
    role_value text;
    role_list text;
    sensitivity_max text;
    sensitivity_list text;
    clause text := '';
BEGIN
    opts := COALESCE(options, '{}'::jsonb);
    IF jsonb_typeof(opts) IS NOT NULL AND jsonb_typeof(opts) <> 'object' THEN
        RAISE EXCEPTION 'options must be a JSON object'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF table_alias IS NULL OR table_alias !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
        RAISE EXCEPTION 'table_alias must be a simple SQL identifier'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    nested_metadata_filter := opts#>'{filters,metadata}';
    metadata_filter := opts->'metadata_filter';
    IF metadata_filter IS NULL
       AND nested_metadata_filter IS NOT NULL
       AND NOT (jsonb_typeof(nested_metadata_filter) = 'object' AND nested_metadata_filter ? 'op') THEN
        metadata_filter := nested_metadata_filter;
    END IF;
    IF metadata_filter IS NOT NULL THEN
        IF jsonb_typeof(metadata_filter) <> 'object' THEN
            RAISE EXCEPTION 'metadata_filter must be a JSON object'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;

        IF metadata_filter <> '{}'::jsonb THEN
            metadata_column := COALESCE(opts->>'metadata_column', 'metadata')::name;
            IF metadata_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
                RAISE EXCEPTION 'metadata_column must be a simple SQL identifier'
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
            clause := clause || format(' AND %I.%I @> %L::jsonb',
                                       table_alias, metadata_column, metadata_filter::text);
        END IF;
    END IF;

    IF opts ? 'tenant_id' THEN
        IF opts->>'tenant_id' IS NULL
           OR opts->>'tenant_id' = ''
           OR opts->>'tenant_id' !~ '^[A-Za-z0-9_.:-]{1,128}$' THEN
            RAISE EXCEPTION 'tenant_id must match ^[A-Za-z0-9_.:-]{1,128}$'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        clause := clause || format(' AND %I.%I = %L',
                                   table_alias, 'tenant_id'::name, opts->>'tenant_id');
    END IF;

    IF opts ? 'namespace' THEN
        namespace_value := opts->>'namespace';
        IF namespace_value IS NULL
           OR namespace_value = ''
           OR namespace_value !~ '^[A-Za-z0-9_.:/-]{1,256}$' THEN
            RAISE EXCEPTION 'namespace must match ^[A-Za-z0-9_.:/-]{1,256}$'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        metadata_column := COALESCE(opts->>'metadata_column', 'metadata')::name;
        IF metadata_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'metadata_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        clause := clause || format(' AND %I.%I @> %L::jsonb',
                                   table_alias,
                                   metadata_column,
                                   jsonb_build_object('namespace', namespace_value)::text);
    END IF;

    nested_acl_filter := opts#>'{filters,acl}';
    acl_filter := opts->'acl_filter';
    IF acl_filter IS NULL
       AND nested_acl_filter IS NOT NULL
       AND NOT (jsonb_typeof(nested_acl_filter) = 'object' AND nested_acl_filter ? 'op') THEN
        acl_filter := nested_acl_filter;
    END IF;
    IF acl_filter IS NOT NULL THEN
        IF jsonb_typeof(acl_filter) <> 'object' THEN
            RAISE EXCEPTION 'acl_filter must be a JSON object'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;

        IF acl_filter <> '{}'::jsonb THEN
            acl_column := COALESCE(opts->>'acl_column', 'acl')::name;
            IF acl_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
                RAISE EXCEPTION 'acl_column must be a simple SQL identifier'
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
            clause := clause || format(' AND %I.%I @> %L::jsonb',
                                       table_alias, acl_column, acl_filter::text);
        END IF;
    END IF;

    IF opts ? 'agent_id' THEN
        agent_id_value := opts->>'agent_id';
        IF agent_id_value IS NULL
           OR agent_id_value = ''
           OR agent_id_value !~ '^[A-Za-z0-9_.:-]{1,128}$' THEN
            RAISE EXCEPTION 'agent_id must match ^[A-Za-z0-9_.:-]{1,128}$'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        acl_column := COALESCE(opts->>'acl_column', 'acl')::name;
        IF acl_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'acl_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        clause := clause || format(
            ' AND (NOT (%1$I.%2$I ? %3$L) OR (%1$I.%2$I->%3$L) ? %4$L)',
            table_alias,
            acl_column,
            'agents',
            agent_id_value
        );
    END IF;

    IF opts ? 'user_id' THEN
        user_id_value := opts->>'user_id';
        IF user_id_value IS NULL
           OR user_id_value = ''
           OR user_id_value !~ '^[A-Za-z0-9_.:@-]{1,256}$' THEN
            RAISE EXCEPTION 'user_id must match ^[A-Za-z0-9_.:@-]{1,256}$'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        acl_column := COALESCE(opts->>'acl_column', 'acl')::name;
        IF acl_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'acl_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        clause := clause || format(
            ' AND (NOT (%1$I.%2$I ? %3$L) OR (%1$I.%2$I->%3$L) ? %4$L)',
            table_alias,
            acl_column,
            'users',
            user_id_value
        );
    END IF;

    role_filters := COALESCE(opts->'user_roles', opts->'allowed_roles');
    IF role_filters IS NOT NULL THEN
        IF jsonb_typeof(role_filters) <> 'array' THEN
            RAISE EXCEPTION 'user_roles/allowed_roles must be a JSON array'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        role_list := NULL;
        FOR role_value IN SELECT jsonb_array_elements_text(role_filters)
        LOOP
            IF role_value IS NULL
               OR role_value = ''
               OR role_value !~ '^[A-Za-z0-9_.:-]{1,128}$' THEN
                RAISE EXCEPTION 'role must match ^[A-Za-z0-9_.:-]{1,128}$'
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
            role_list := concat_ws(', ', role_list, format('%L', role_value));
        END LOOP;

        acl_column := COALESCE(opts->>'acl_column', 'acl')::name;
        IF acl_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'acl_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF role_list IS NULL THEN
            clause := clause || format(' AND NOT (%I.%I ? %L)', table_alias, acl_column, 'roles');
        ELSE
            clause := clause || format(
                ' AND (NOT (%1$I.%2$I ? %3$L) OR (%1$I.%2$I->%3$L) ?| ARRAY[%4$s]::text[])',
                table_alias,
                acl_column,
                'roles',
                role_list
            );
        END IF;
    END IF;

    IF opts ? 'sensitivity_max' THEN
        sensitivity_max := opts->>'sensitivity_max';
        IF sensitivity_max = 'public' THEN
            sensitivity_list := '''public''';
        ELSIF sensitivity_max = 'internal' THEN
            sensitivity_list := '''public'', ''internal''';
        ELSIF sensitivity_max = 'confidential' THEN
            sensitivity_list := '''public'', ''internal'', ''confidential''';
        ELSIF sensitivity_max = 'restricted' THEN
            sensitivity_list := '''public'', ''internal'', ''confidential'', ''restricted''';
        ELSE
            RAISE EXCEPTION 'sensitivity_max must be public, internal, confidential, or restricted'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;

        metadata_column := COALESCE(opts->>'metadata_column', 'metadata')::name;
        acl_column := COALESCE(opts->>'acl_column', 'acl')::name;
        IF metadata_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'metadata_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        IF acl_column::text !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'acl_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        clause := clause || format(
            ' AND COALESCE(%1$I.%2$I->>%5$L, %1$I.%3$I->>%5$L, %4$L) IN (%6$s)',
            table_alias,
            metadata_column,
            acl_column,
            'public',
            'sensitivity_level',
            sensitivity_list
        );
    END IF;

    scalar_filters := COALESCE(opts->'filters', '{}'::jsonb);
    IF jsonb_typeof(scalar_filters) IS NOT NULL AND jsonb_typeof(scalar_filters) <> 'object' THEN
        RAISE EXCEPTION 'filters must be a JSON object'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    FOR filter_key, filter_value IN
        SELECT key, value
        FROM jsonb_each(scalar_filters)
    LOOP
        IF filter_key = 'metadata'
           AND NOT (jsonb_typeof(filter_value) = 'object' AND filter_value ? 'op') THEN
            CONTINUE;
        END IF;
        IF filter_key = 'acl'
           AND NOT (jsonb_typeof(filter_value) = 'object' AND filter_value ? 'op') THEN
            CONTINUE;
        END IF;

        IF filter_key IS NULL OR filter_key !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'filter column must be a simple SQL identifier: %', filter_key
                USING ERRCODE = 'invalid_parameter_value';
        END IF;

        IF jsonb_typeof(filter_value) = 'object' AND filter_value ? 'op' THEN
            filter_op := lower(filter_value->>'op');
            op_value := filter_value->'value';
            IF filter_op IS NULL OR filter_op = '' THEN
                RAISE EXCEPTION 'filter op must not be empty for column %', filter_key
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
            IF filter_op IN ('eq', 'ne', 'in', 'contains') AND NOT (filter_value ? 'value') THEN
                RAISE EXCEPTION 'filter op % requires value for column %', filter_op, filter_key
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;

            IF filter_op = 'eq' THEN
                clause := clause || format(' AND to_jsonb(%I.%I) = %L::jsonb',
                                           table_alias, filter_key::name, op_value::text);
            ELSIF filter_op = 'ne' THEN
                clause := clause || format(' AND to_jsonb(%I.%I) <> %L::jsonb',
                                           table_alias, filter_key::name, op_value::text);
            ELSIF filter_op = 'in' THEN
                IF jsonb_typeof(op_value) <> 'array' THEN
                    RAISE EXCEPTION 'in filter value must be an array for column %', filter_key
                        USING ERRCODE = 'invalid_parameter_value';
                END IF;
                SELECT string_agg(format('%L::jsonb', elem.value::text), ', ')
                INTO value_list
                FROM jsonb_array_elements(op_value) AS elem(value);
                IF value_list IS NULL THEN
                    clause := clause || ' AND false';
                ELSE
                    clause := clause || format(' AND to_jsonb(%I.%I) IN (%s)',
                                               table_alias, filter_key::name, value_list);
                END IF;
            ELSIF filter_op = 'contains' THEN
                clause := clause || format(' AND %I.%I @> %L::jsonb',
                                           table_alias, filter_key::name, op_value::text);
            ELSIF filter_op = 'is_null' THEN
                IF op_value IS NULL OR op_value = 'true'::jsonb THEN
                    clause := clause || format(' AND %I.%I IS NULL',
                                               table_alias, filter_key::name);
                ELSE
                    clause := clause || format(' AND %I.%I IS NOT NULL',
                                               table_alias, filter_key::name);
                END IF;
            ELSE
                RAISE EXCEPTION 'unsupported filter op for column %: %', filter_key, filter_op
                    USING ERRCODE = 'invalid_parameter_value';
            END IF;
        ELSE
            clause := clause || format(' AND to_jsonb(%I.%I) = %L::jsonb',
                                       table_alias, filter_key::name, filter_value::text);
        END IF;
    END LOOP;

    IF opts ? 'soft_delete_column' THEN
        IF opts->>'soft_delete_column' IS NULL
           OR opts->>'soft_delete_column' !~ '^[A-Za-z_][A-Za-z0-9_]*$' THEN
            RAISE EXCEPTION 'soft_delete_column must be a simple SQL identifier'
                USING ERRCODE = 'invalid_parameter_value';
        END IF;
        soft_delete_column := (opts->>'soft_delete_column')::name;
        clause := clause || format(' AND %I.%I IS NULL', table_alias, soft_delete_column);
    END IF;

    RETURN clause;
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
    filter_clause text;
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
    filter_clause := pg_retrieval_engine_build_filter_clause('d', options);

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
                d.%1$I::bigint AS id,
                (d.%2$I %8$s $1)::real AS vector_distance,
                row_number() OVER (ORDER BY d.%2$I %8$s $1, d.%1$I)::integer AS vector_rank
            FROM %3$s AS d
            WHERE d.%2$I IS NOT NULL %11$s
            ORDER BY d.%2$I %8$s $1, d.%1$I
            LIMIT %4$s
        ),
        fts_results AS (
            SELECT
                d.%1$I::bigint AS id,
                pg_catalog.%9$s(d.%5$I, $2, %10$s)::real AS fts_score,
                row_number() OVER (ORDER BY pg_catalog.%9$s(d.%5$I, $2, %10$s) DESC, d.%1$I)::integer AS fts_rank
            FROM %3$s AS d
            WHERE d.%5$I @@ $2 %11$s
            ORDER BY pg_catalog.%9$s(d.%5$I, $2, %10$s) DESC, d.%1$I
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
        normalization,
        filter_clause)
    USING query_vector, query_tsquery, vector_weight, rrf_k, fts_weight;
END;
$$;

COMMENT ON FUNCTION pg_retrieval_engine_rrf_fuse(bigint[], bigint[], integer, double precision, double precision, double precision)
IS 'Fuse vector and full-text ranked ID lists with Reciprocal Rank Fusion.';

COMMENT ON FUNCTION pg_retrieval_engine_build_filter_clause(text, jsonb)
IS 'Build a safe SQL filter clause for hybrid search options. Supports tenant_id, scalar filters, filter ops, metadata_filter, acl_filter, and soft_delete_column.';

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_search(regclass, name, name, name, vector, tsquery, integer, jsonb)
IS 'Run pgvector and PostgreSQL tsvector retrieval over one table, apply optional filters, then merge rankings with Reciprocal Rank Fusion.';

CREATE FUNCTION pg_retrieval_engine_hybrid_search_batch(
    table_name regclass,
    id_column name,
    vector_column name,
    tsvector_column name,
    query_vectors vector[],
    query_tsqueries tsquery[],
    k integer,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    query_no integer,
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
    q record;
BEGIN
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF cardinality(query_vectors) < 1 THEN
        RAISE EXCEPTION 'query_vectors must not be empty' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF cardinality(query_vectors) <> cardinality(query_tsqueries) THEN
        RAISE EXCEPTION 'query_vectors and query_tsqueries length must match'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    FOR q IN
        SELECT *
        FROM unnest(query_vectors, query_tsqueries) WITH ORDINALITY
            AS queries(query_vector, query_tsquery, query_no)
    LOOP
        RETURN QUERY
        SELECT q.query_no::integer,
               h.id,
               h.rrf_score,
               h.vector_rank,
               h.fts_rank,
               h.vector_distance,
               h.fts_score
        FROM pg_retrieval_engine_hybrid_search(
            table_name,
            id_column,
            vector_column,
            tsvector_column,
            q.query_vector,
            q.query_tsquery,
            k,
            options
        ) AS h;
    END LOOP;
END;
$$;

CREATE FUNCTION pg_retrieval_engine_search_chunks(
    query_vector vector,
    query_tsquery tsquery,
    k integer,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(
    chunk_id bigint,
    document_id bigint,
    parent_chunk_id bigint,
    chunk_type text,
    content text,
    context_content text,
    metadata jsonb,
    citation_metadata jsonb,
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
    opts jsonb;
    search_options jsonb;
    return_parent boolean;
BEGIN
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    opts := COALESCE(options, '{}'::jsonb);
    IF jsonb_typeof(COALESCE(opts->'filters', '{}'::jsonb)) <> 'object' THEN
        RAISE EXCEPTION 'filters must be a JSON object'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    return_parent := COALESCE((opts->>'return_parent')::boolean, false);
    search_options := jsonb_set(
        opts,
        '{filters}',
        COALESCE(opts->'filters', '{}'::jsonb) || '{"chunk_type":"child"}'::jsonb,
        true
    );

    RETURN QUERY
    SELECT h.id AS chunk_id,
           c.document_id,
           c.parent_chunk_id,
           c.chunk_type,
           c.content,
           CASE WHEN return_parent AND p.id IS NOT NULL THEN p.content ELSE c.content END AS context_content,
           c.metadata,
           c.citation_metadata,
           h.rrf_score,
           h.vector_rank,
           h.fts_rank,
           h.vector_distance,
           h.fts_score
    FROM pg_retrieval_engine_hybrid_search(
        'pg_retrieval_engine_chunks'::regclass,
        'id',
        'embedding',
        'search_vector',
        query_vector,
        query_tsquery,
        k,
        search_options
    ) AS h
    JOIN pg_retrieval_engine_chunks c ON c.id = h.id
    LEFT JOIN pg_retrieval_engine_chunks p ON p.id = c.parent_chunk_id
    ORDER BY h.rrf_score DESC,
             LEAST(COALESCE(h.vector_rank, 2147483647),
                   COALESCE(h.fts_rank, 2147483647)),
             h.id;
END;
$$;

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_search_batch(regclass, name, name, name, vector[], tsquery[], integer, jsonb)
IS 'Run pgvector + tsvector RRF hybrid search for a batch of query vectors and tsqueries.';

COMMENT ON FUNCTION pg_retrieval_engine_search_chunks(vector, tsquery, integer, jsonb)
IS 'Search extension-managed chunks and return content, parent context, metadata, citations, and ranking diagnostics for RAG/agent tools.';

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
    filter_clause text;
    faiss_distance_order text;
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
    filter_clause := pg_retrieval_engine_build_filter_clause('d', options);
    faiss_distance_order := COALESCE(options->>'faiss_distance_order', 'asc');

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
    IF faiss_distance_order NOT IN ('asc', 'desc') THEN
        RAISE EXCEPTION 'faiss_distance_order must be asc or desc'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY EXECUTE format($sql$
        WITH raw_vector_results AS (
            SELECT
                s.id,
                s.distance AS vector_distance,
                row_number() OVER (ORDER BY s.distance %11$s, s.id)::integer AS raw_vector_rank
            FROM pg_retrieval_engine_index_search($1, $2, %4$s, $3) AS s
        ),
        vector_results AS (
            SELECT
                r.id,
                r.vector_distance,
                row_number() OVER (ORDER BY r.raw_vector_rank, r.id)::integer AS vector_rank
            FROM raw_vector_results r
            JOIN %3$s AS d ON d.%1$I::bigint = r.id
            WHERE true %10$s
            ORDER BY r.raw_vector_rank, r.id
            LIMIT %4$s
        ),
        fts_results AS (
            SELECT
                d.%1$I::bigint AS id,
                pg_catalog.%8$s(d.%2$I, $4, %9$s)::real AS fts_score,
                row_number() OVER (ORDER BY pg_catalog.%8$s(d.%2$I, $4, %9$s) DESC, d.%1$I)::integer AS fts_rank
            FROM %3$s AS d
            WHERE d.%2$I @@ $4 %10$s
            ORDER BY pg_catalog.%8$s(d.%2$I, $4, %9$s) DESC, d.%1$I
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
        normalization,
        filter_clause,
        faiss_distance_order)
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
    candidate_count integer;
    dropped_count integer;
    overlap_ratio double precision;
    missing_relevant bigint[];
    recalled_relevant bigint[];
    reason text;
    opts jsonb;
BEGIN
    opts := COALESCE(options, '{}'::jsonb);
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

    SELECT count(*)::integer INTO candidate_count
    FROM (
        SELECT DISTINCT id FROM unnest(vector_ids) AS v(id)
        UNION
        SELECT DISTINCT id FROM unnest(fts_ids) AS f(id)
    ) candidate_ids;

    dropped_count := GREATEST(candidate_count - final_count, 0);
    overlap_ratio := CASE WHEN candidate_count > 0
                          THEN overlap_count::double precision / candidate_count::double precision
                          ELSE 0.0
                     END;

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
            'candidate', candidate_count,
            'overlap', overlap_count,
            'vector_only', vector_only_count,
            'fts_only', fts_only_count,
            'dropped_after_candidate_generation', dropped_count
        ),
        'fusion', jsonb_build_object(
            'method', COALESCE(opts->>'fusion_method', 'rrf'),
            'rrf_k', COALESCE(opts->'rrf_k', '60'::jsonb),
            'vector_weight', COALESCE(opts->'vector_weight', opts->'dense_weight', '1.0'::jsonb),
            'fts_weight', COALESCE(opts->'fts_weight', opts->'sparse_weight', '1.0'::jsonb),
            'overlap_ratio', overlap_ratio
        ),
        'filters', jsonb_build_object(
            'scalar', COALESCE(opts->'filters', '{}'::jsonb),
            'metadata_filter', COALESCE(opts->'metadata_filter', opts#>'{filters,metadata}', '{}'::jsonb),
            'acl_filter', COALESCE(opts->'acl_filter', opts#>'{filters,acl}', '{}'::jsonb),
            'tenant_id', opts->>'tenant_id',
            'namespace', opts->>'namespace',
            'agent_id', opts->>'agent_id',
            'user_id', opts->>'user_id',
            'user_roles', COALESCE(opts->'user_roles', opts->'allowed_roles', '[]'::jsonb),
            'sensitivity_max', opts->>'sensitivity_max',
            'soft_delete_column', opts->>'soft_delete_column'
        ),
        'latency_ms', COALESCE(opts->'latency_ms', '{}'::jsonb),
        'candidates', jsonb_build_object(
            'vector_ids', vector_ids,
            'fts_ids', fts_ids,
            'final_ids', final_ids
        ),
        'relevance', jsonb_build_object(
            'recalled', recalled_relevant,
            'missing', missing_relevant
        ),
        'likely_failure_reason', reason,
        'options', opts
    );
END;
$$;

CREATE FUNCTION pg_retrieval_engine_hybrid_autotune(
    mode text DEFAULT 'balanced',
    k integer DEFAULT 10,
    options jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    opts jsonb;
    mode_norm text;
    target_recall double precision;
    target_p95_ms double precision;
    max_candidate_k integer;
    multiplier integer;
    recommended_vector_k integer;
    recommended_fts_k integer;
    recommended_rerank_k integer;
    recommended_rrf_k integer;
    hnsw_ef_search integer;
    ivfflat_probes integer;
BEGIN
    opts := COALESCE(options, '{}'::jsonb);
    mode_norm := lower(COALESCE(mode, 'balanced'));

    IF mode_norm NOT IN ('latency', 'balanced', 'recall') THEN
        RAISE EXCEPTION 'mode must be latency, balanced, or recall'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF k < 1 THEN
        RAISE EXCEPTION 'k must be >= 1' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    target_recall := COALESCE((opts->>'target_recall')::double precision, 0.90);
    target_p95_ms := COALESCE((opts->>'target_p95_ms')::double precision, NULL);
    max_candidate_k := COALESCE((opts->>'max_candidate_k')::integer, 1000);

    IF target_recall <= 0 OR target_recall > 1 THEN
        RAISE EXCEPTION 'target_recall must be in range (0, 1]'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF max_candidate_k < k THEN
        RAISE EXCEPTION 'max_candidate_k must be >= k'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF mode_norm = 'latency' THEN
        multiplier := 4;
        recommended_rrf_k := 40;
        hnsw_ef_search := 40;
        ivfflat_probes := 4;
    ELSIF mode_norm = 'recall' THEN
        multiplier := 16;
        recommended_rrf_k := 80;
        hnsw_ef_search := 128;
        ivfflat_probes := 32;
    ELSE
        multiplier := 8;
        recommended_rrf_k := 60;
        hnsw_ef_search := 64;
        ivfflat_probes := 10;
    END IF;

    IF target_recall >= 0.95 THEN
        multiplier := multiplier * 2;
        hnsw_ef_search := hnsw_ef_search * 2;
        ivfflat_probes := ivfflat_probes * 2;
    END IF;

    IF target_p95_ms IS NOT NULL AND target_p95_ms < 50 AND mode_norm <> 'recall' THEN
        multiplier := GREATEST(multiplier / 2, 2);
        hnsw_ef_search := GREATEST(hnsw_ef_search / 2, 16);
        ivfflat_probes := GREATEST(ivfflat_probes / 2, 1);
    END IF;

    recommended_vector_k := LEAST(max_candidate_k, GREATEST(k, k * multiplier));
    recommended_fts_k := LEAST(max_candidate_k, GREATEST(k, k * multiplier));
    recommended_rerank_k := LEAST(max_candidate_k, GREATEST(k, k * GREATEST(multiplier / 2, 2)));

    RETURN jsonb_build_object(
        'mode', mode_norm,
        'target', jsonb_build_object(
            'k', k,
            'target_recall', target_recall,
            'target_p95_ms', target_p95_ms
        ),
        'recommended_options', jsonb_build_object(
            'vector_k', recommended_vector_k,
            'fts_k', recommended_fts_k,
            'rrf_k', recommended_rrf_k,
            'vector_weight', COALESCE(opts->'vector_weight', '1.0'::jsonb),
            'fts_weight', COALESCE(opts->'fts_weight', '1.0'::jsonb),
            'rerank_k', recommended_rerank_k
        ),
        'pgvector_knobs', jsonb_build_object(
            'hnsw.ef_search', hnsw_ef_search,
            'ivfflat.probes', ivfflat_probes
        ),
        'notes', jsonb_build_array(
            'Heuristic recommendation only; validate with fixed qrels and latency measurements.',
            'Use pgvector as the production-consistent dense path; use FAISS only as an optional accelerator.'
        )
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

COMMENT ON FUNCTION pg_retrieval_engine_claim_embedding_jobs(bigint, integer, text, integer, integer)
IS 'Atomically claim pending, failed, or timed-out embedding jobs with FOR UPDATE SKIP LOCKED for external embedding workers.';

COMMENT ON FUNCTION pg_retrieval_engine_embedding_job_complete(bigint, vector, jsonb, integer, text)
IS 'Mark one claimed running embedding job complete, optionally fence by claim attempt and worker, validate vector dimensions, attach the current vector to its chunk, and upsert the versioned embedding row.';

COMMENT ON FUNCTION pg_retrieval_engine_embedding_job_fail(bigint, text, jsonb, integer, text)
IS 'Mark an embedding job failed, optionally fence by claim attempt and worker, clear its lease, and store error metadata for retry diagnostics.';

COMMENT ON FUNCTION pg_retrieval_engine_activate_embedding_version(bigint, text)
IS 'Promote current versioned chunk embeddings to the latest chunk embedding column for one embedding version and optional tenant.';

COMMENT ON FUNCTION pg_retrieval_engine_pgvector_index_create(regclass, name, text, text, jsonb)
IS 'Create a pgvector HNSW or IVFFlat index for a vector column.';

COMMENT ON FUNCTION pg_retrieval_engine_tsvector_index_create(regclass, name)
IS 'Create a GIN index for a tsvector column.';

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_search_faiss(regclass, name, name, text, vector, tsquery, integer, jsonb)
IS 'Run FAISS dense retrieval and PostgreSQL tsvector retrieval, then fuse with RRF.';

COMMENT ON FUNCTION pg_retrieval_engine_rerank_with_citations(bigint[], jsonb[], integer, double precision[], double precision[], double precision[], double precision[], jsonb)
IS 'Rerank candidate IDs and attach citation metadata aligned to the input candidate order.';

COMMENT ON FUNCTION pg_retrieval_engine_retrieval_explain(bigint[], bigint[], bigint[], bigint[], jsonb)
IS 'Summarize retrieval stage counts, filters, fusion diagnostics, latency hints, and likely recall failure reasons.';

COMMENT ON FUNCTION pg_retrieval_engine_hybrid_autotune(text, integer, jsonb)
IS 'Recommend pgvector hybrid search knobs for latency, balanced, or recall modes. Validate recommendations with fixed qrels.';
