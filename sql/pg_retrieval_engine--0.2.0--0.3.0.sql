-- Upgrade script from 0.2.0 to 0.3.0

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
