-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_faiss" to load this file. \quit

CREATE FUNCTION pg_faiss_index_create(
    name text,
    dim integer,
    metric text,
    index_type text,
    options jsonb DEFAULT '{}'::jsonb,
    device text DEFAULT 'cpu'
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_index_create'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_train(
    name text,
    training_vectors vector[]
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_index_train'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_add(
    name text,
    ids bigint[],
    vectors vector[]
) RETURNS bigint
AS 'MODULE_PATHNAME', 'pg_faiss_index_add'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_search(
    name text,
    query vector,
    k integer,
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_faiss_index_search'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_search_batch(
    name text,
    queries vector[],
    k integer,
    search_params jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE(query_no integer, id bigint, distance real)
AS 'MODULE_PATHNAME', 'pg_faiss_index_search_batch'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_save(
    name text,
    path text
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_index_save'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_load(
    name text,
    path text,
    device text DEFAULT 'cpu'
) RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_index_load'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_index_stats(name text)
RETURNS jsonb
AS 'MODULE_PATHNAME', 'pg_faiss_index_stats'
LANGUAGE C STABLE STRICT;

CREATE FUNCTION pg_faiss_index_drop(name text)
RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_index_drop'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION pg_faiss_reset()
RETURNS void
AS 'MODULE_PATHNAME', 'pg_faiss_reset'
LANGUAGE C VOLATILE;

COMMENT ON FUNCTION pg_faiss_index_create(text, integer, text, text, jsonb, text)
IS 'Create a FAISS index. index_type: hnsw|ivfflat|ivfpq, metric: l2|ip|cosine, device: cpu|gpu.';

COMMENT ON FUNCTION pg_faiss_index_train(text, vector[])
IS 'Train IVF indexes using vector[] input.';

COMMENT ON FUNCTION pg_faiss_index_add(text, bigint[], vector[])
IS 'Bulk add vectors with explicit IDs.';

COMMENT ON FUNCTION pg_faiss_index_search(text, vector, integer, jsonb)
IS 'Search nearest neighbors and return (id, distance).';

COMMENT ON FUNCTION pg_faiss_index_search_batch(text, vector[], integer, jsonb)
IS 'Batch nearest-neighbor search and return (query_no, id, distance).';

COMMENT ON FUNCTION pg_faiss_index_save(text, text)
IS 'Persist index to disk. Metadata is stored at <path>.meta.';

COMMENT ON FUNCTION pg_faiss_index_load(text, text, text)
IS 'Load persisted index from disk.';

COMMENT ON FUNCTION pg_faiss_index_stats(text)
IS 'Return index metadata and runtime statistics as jsonb.';

COMMENT ON FUNCTION pg_faiss_index_drop(text)
IS 'Drop one in-memory index.';

COMMENT ON FUNCTION pg_faiss_reset()
IS 'Drop all in-memory indexes in current backend process.';
