extern "C" {
#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"
#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "lib/stringinfo.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/hsearch.h"
#include "utils/json.h"
#include "utils/jsonb.h"
#include "utils/memutils.h"
#include "utils/numeric.h"
#include "utils/tuplestore.h"
}

#include "pg_faiss.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <faiss/IndexFlat.h>
#include <faiss/IndexHNSW.h>
#include <faiss/IndexIDMap.h>
#include <faiss/IndexIVF.h>
#include <faiss/IndexIVFFlat.h>
#include <faiss/IndexIVFPQ.h>
#include <faiss/index_io.h>

#ifdef USE_FAISS_GPU
#include <faiss/gpu/GpuCloner.h>
#endif

extern "C" {
PG_MODULE_MAGIC;
}

extern "C" {
PG_FUNCTION_INFO_V1(pg_faiss_index_create);
PG_FUNCTION_INFO_V1(pg_faiss_index_train);
PG_FUNCTION_INFO_V1(pg_faiss_index_add);
PG_FUNCTION_INFO_V1(pg_faiss_index_search);
PG_FUNCTION_INFO_V1(pg_faiss_index_search_batch);
PG_FUNCTION_INFO_V1(pg_faiss_index_save);
PG_FUNCTION_INFO_V1(pg_faiss_index_load);
PG_FUNCTION_INFO_V1(pg_faiss_index_stats);
PG_FUNCTION_INFO_V1(pg_faiss_index_drop);
PG_FUNCTION_INFO_V1(pg_faiss_reset);
}

typedef struct PgVector {
  int32 vl_len_;
  int16 dim;
  int16 unused;
  float x[FLEXIBLE_ARRAY_MEMBER];
} PgVector;

static HTAB* pg_faiss_registry = NULL;

static inline void ensure_registry(void) {
  if (pg_faiss_registry == NULL) {
    HASHCTL ctl;

    memset(&ctl, 0, sizeof(ctl));
    ctl.keysize = PG_FAISS_MAX_INDEX_NAME;
    ctl.entrysize = sizeof(PgFaissIndexEntry);
    ctl.hcxt = TopMemoryContext;

    pg_faiss_registry =
        hash_create("pg_faiss index registry", 128, &ctl, HASH_ELEM | HASH_STRINGS | HASH_CONTEXT);

    if (pg_faiss_registry == NULL)
      ereport(ERROR,
              (errcode(ERRCODE_OUT_OF_MEMORY), errmsg("failed to create pg_faiss registry")));
  }
}

static inline const char* metric_name(int metric) {
  switch (metric) {
    case PG_FAISS_METRIC_L2:
      return "l2";
    case PG_FAISS_METRIC_IP:
      return "ip";
    case PG_FAISS_METRIC_COSINE:
      return "cosine";
    default:
      return "unknown";
  }
}

static inline const char* index_type_name(int index_type) {
  switch (index_type) {
    case PG_FAISS_INDEX_HNSW:
      return "hnsw";
    case PG_FAISS_INDEX_IVF_FLAT:
      return "ivfflat";
    case PG_FAISS_INDEX_IVF_PQ:
      return "ivfpq";
    default:
      return "unknown";
  }
}

static inline const char* device_name(int device) {
  return device == PG_FAISS_DEVICE_GPU ? "gpu" : "cpu";
}

static inline faiss::MetricType to_faiss_metric(int metric) {
  if (metric == PG_FAISS_METRIC_L2) return faiss::METRIC_L2;

  return faiss::METRIC_INNER_PRODUCT;
}

static inline PgFaissIndexEntry* lookup_entry(const char* name) {
  if (pg_faiss_registry == NULL) return NULL;

  return (PgFaissIndexEntry*)hash_search(pg_faiss_registry, name, HASH_FIND, NULL);
}

static inline faiss::Index* unwrap_idmap(faiss::Index* index) {
  faiss::IndexIDMap* idmap = dynamic_cast<faiss::IndexIDMap*>(index);

  if (idmap != NULL) return idmap->index;

  return index;
}

static inline void normalize_one(float* vec, int dim) {
  float norm = 0.0f;

  for (int i = 0; i < dim; i++) norm += vec[i] * vec[i];

  norm = sqrtf(norm);

  if (norm > 0.0f) {
    for (int i = 0; i < dim; i++) vec[i] /= norm;
  }
}

static inline void normalize_many(float* vecs, int64 n, int dim) {
  for (int64 i = 0; i < n; i++) normalize_one(&vecs[i * dim], dim);
}

static inline faiss::Index* active_index(PgFaissIndexEntry* entry) {
#ifdef USE_FAISS_GPU
  if (entry->device == PG_FAISS_DEVICE_GPU) {
    if (entry->gpu_index == NULL)
      ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                      errmsg("GPU index for \"%s\" is not initialized", entry->name)));

    return entry->gpu_index;
  }
#endif

  if (entry->cpu_index == NULL)
    ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                    errmsg("CPU index for \"%s\" is not initialized", entry->name)));

  return entry->cpu_index;
}

#ifdef USE_FAISS_GPU
static void rebuild_gpu_index(PgFaissIndexEntry* entry) {
  if (entry->device != PG_FAISS_DEVICE_GPU) return;

  if (entry->gpu_resources == NULL) entry->gpu_resources = new faiss::gpu::StandardGpuResources();

  if (entry->gpu_index != NULL) {
    delete entry->gpu_index;
    entry->gpu_index = NULL;
  }

  entry->gpu_index =
      faiss::gpu::index_cpu_to_gpu(entry->gpu_resources, entry->gpu_device, entry->cpu_index);
}

static void sync_gpu_to_cpu(PgFaissIndexEntry* entry) {
  if (entry->device != PG_FAISS_DEVICE_GPU || entry->gpu_index == NULL) return;

  faiss::Index* new_cpu = faiss::gpu::index_gpu_to_cpu(entry->gpu_index);

  if (entry->cpu_index != NULL) delete entry->cpu_index;

  entry->cpu_index = new_cpu;
}
#endif

static inline void free_entry_resources(PgFaissIndexEntry* entry) {
#ifdef USE_FAISS_GPU
  if (entry->gpu_index != NULL) {
    delete entry->gpu_index;
    entry->gpu_index = NULL;
  }

  if (entry->gpu_resources != NULL) {
    delete entry->gpu_resources;
    entry->gpu_resources = NULL;
  }
#endif

  if (entry->cpu_index != NULL) {
    delete entry->cpu_index;
    entry->cpu_index = NULL;
  }
}

static JsonbValue* jsonb_find_key(Jsonb* json, const char* key) {
  JsonbValue key_value;

  if (json == NULL) return NULL;

  key_value.type = jbvString;
  key_value.val.string.val = const_cast<char*>(key);
  key_value.val.string.len = strlen(key);

  return findJsonbValueFromContainer(&json->root, JB_FOBJECT, &key_value);
}

static bool jsonb_get_int32(Jsonb* json, const char* key, int32* out) {
  JsonbValue* value = jsonb_find_key(json, key);

  if (value == NULL) return false;

  if (value->type == jbvNumeric) {
    *out = DatumGetInt32(DirectFunctionCall1(numeric_int4, NumericGetDatum(value->val.numeric)));
    return true;
  }

  if (value->type == jbvString) {
    std::string text(value->val.string.val, value->val.string.len);

    try {
      *out = std::stoi(text);
      return true;
    } catch (const std::exception&) {
      ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                      errmsg("invalid integer value for option \"%s\"", key)));
    }
  }

  ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                  errmsg("option \"%s\" must be an integer", key)));

  return false;
}

static int32 jsonb_option_int32(Jsonb* json, const char* key, int32 default_value, int32 min_value,
                                int32 max_value) {
  int32 value = default_value;

  if (!jsonb_get_int32(json, key, &value)) return default_value;

  if (value < min_value || value > max_value)
    ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
             errmsg("option \"%s\" out of range (%d..%d): %d", key, min_value, max_value, value)));

  return value;
}

static inline PgVector* datum_to_pgvector(Datum datum) {
  return (PgVector*)PG_DETOAST_DATUM(datum);
}

static void read_vector_array(ArrayType* arr, int expected_dim, std::vector<float>& out,
                              int64* num_vectors) {
  Datum* elements = NULL;
  bool* nulls = NULL;
  int nelems = 0;

  if (ARR_NDIM(arr) != 1)
    ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("vector[] argument must be one-dimensional")));

  deconstruct_array(arr, ARR_ELEMTYPE(arr), -1, false, 'i', &elements, &nulls, &nelems);

  if (nelems <= 0)
    ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("vector[] argument must not be empty")));

  out.resize((size_t)nelems * (size_t)expected_dim);

  for (int i = 0; i < nelems; i++) {
    PgVector* vec;

    if (nulls[i])
      ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
                      errmsg("vector[] argument must not contain NULL values")));

    vec = datum_to_pgvector(elements[i]);

    if (vec->dim != expected_dim)
      ereport(ERROR,
              (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
               errmsg("vector dimension mismatch: expected %d, got %d", expected_dim, vec->dim)));

    memcpy(&out[(size_t)i * (size_t)expected_dim], vec->x, sizeof(float) * expected_dim);
  }

  pfree(elements);
  pfree(nulls);

  *num_vectors = nelems;
}

static void read_ids_array(ArrayType* arr, std::vector<faiss::idx_t>& ids) {
  Datum* elements = NULL;
  bool* nulls = NULL;
  int nelems = 0;

  if (ARR_NDIM(arr) != 1)
    ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("ids argument must be one-dimensional bigint[]")));

  if (ARR_ELEMTYPE(arr) != INT8OID)
    ereport(ERROR, (errcode(ERRCODE_DATATYPE_MISMATCH), errmsg("ids argument must be bigint[]")));

  deconstruct_array(arr, INT8OID, 8, true, 'd', &elements, &nulls, &nelems);

  if (nelems <= 0)
    ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("ids argument must not be empty")));

  ids.resize(nelems);

  for (int i = 0; i < nelems; i++) {
    if (nulls[i])
      ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
                      errmsg("ids argument must not contain NULL values")));

    ids[i] = (faiss::idx_t)DatumGetInt64(elements[i]);
  }

  pfree(elements);
  pfree(nulls);
}

static void apply_search_params(PgFaissIndexEntry* entry, faiss::Index* index, Jsonb* search_params,
                                int* old_ef_search, int* old_nprobe, bool* changed_ef_search,
                                bool* changed_nprobe) {
  faiss::Index* base = unwrap_idmap(index);

  *changed_ef_search = false;
  *changed_nprobe = false;

  if (entry->index_type == PG_FAISS_INDEX_HNSW) {
    faiss::IndexHNSW* hnsw = dynamic_cast<faiss::IndexHNSW*>(base);

    if (hnsw != NULL) {
      int32 ef_search = entry->hnsw_ef_search;

      if (jsonb_get_int32(search_params, "ef_search", &ef_search)) {
        if (ef_search < 1 || ef_search > 1000000)
          ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                          errmsg("ef_search must be in range 1..1000000")));
      }

      *old_ef_search = hnsw->hnsw.efSearch;
      hnsw->hnsw.efSearch = ef_search;
      *changed_ef_search = true;
    }
  }

  if (entry->index_type == PG_FAISS_INDEX_IVF_FLAT || entry->index_type == PG_FAISS_INDEX_IVF_PQ) {
    faiss::IndexIVF* ivf = dynamic_cast<faiss::IndexIVF*>(base);

    if (ivf != NULL) {
      int32 nprobe = entry->ivf_nprobe;

      if (jsonb_get_int32(search_params, "nprobe", &nprobe)) {
        if (nprobe < 1 || nprobe > 1000000)
          ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                          errmsg("nprobe must be in range 1..1000000")));
      }

      *old_nprobe = ivf->nprobe;
      ivf->nprobe = nprobe;
      *changed_nprobe = true;
    }
  }
}

static void restore_search_params(faiss::Index* index, int old_ef_search, int old_nprobe,
                                  bool changed_ef_search, bool changed_nprobe) {
  faiss::Index* base = unwrap_idmap(index);

  if (changed_ef_search) {
    faiss::IndexHNSW* hnsw = dynamic_cast<faiss::IndexHNSW*>(base);

    if (hnsw != NULL) hnsw->hnsw.efSearch = old_ef_search;
  }

  if (changed_nprobe) {
    faiss::IndexIVF* ivf = dynamic_cast<faiss::IndexIVF*>(base);

    if (ivf != NULL) ivf->nprobe = old_nprobe;
  }
}

static void materialize_result_begin(FunctionCallInfo fcinfo, Tuplestorestate** tupstore,
                                     TupleDesc* tupdesc, ReturnSetInfo** rsinfo) {
  MemoryContext oldcontext;

  *rsinfo = (ReturnSetInfo*)fcinfo->resultinfo;

  if (*rsinfo == NULL || !IsA(*rsinfo, ReturnSetInfo))
    ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                    errmsg("set-valued function called in context that cannot accept a set")));

  if (!((*rsinfo)->allowedModes & SFRM_Materialize))
    ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("materialize mode required")));

  if (get_call_result_type(fcinfo, NULL, tupdesc) != TYPEFUNC_COMPOSITE)
    ereport(ERROR, (errcode(ERRCODE_DATATYPE_MISMATCH), errmsg("return type must be a row type")));

  oldcontext = MemoryContextSwitchTo((*rsinfo)->econtext->ecxt_per_query_memory);
  *tupstore = tuplestore_begin_heap(true, false, work_mem);
  MemoryContextSwitchTo(oldcontext);

  BlessTupleDesc(*tupdesc);
}

static void materialize_result_end(ReturnSetInfo* rsinfo, Tuplestorestate* tupstore,
                                   TupleDesc tupdesc) {
  rsinfo->returnMode = SFRM_Materialize;
  rsinfo->setResult = tupstore;
  rsinfo->setDesc = tupdesc;
}

static void write_metadata_file(const PgFaissIndexEntry* entry, const char* path) {
  std::ofstream out(std::string(path) + ".meta", std::ios::trunc);

  if (!out.is_open())
    ereport(ERROR, (errcode(ERRCODE_IO_ERROR),
                    errmsg("could not open metadata file \"%s.meta\" for write", path)));

  out << "version=" << PG_FAISS_VERSION << "\n";
  out << "metric=" << metric_name(entry->metric) << "\n";
  out << "index_type=" << index_type_name(entry->index_type) << "\n";
  out << "dim=" << entry->dim << "\n";
  out << "hnsw_m=" << entry->hnsw_m << "\n";
  out << "hnsw_ef_construction=" << entry->hnsw_ef_construction << "\n";
  out << "hnsw_ef_search=" << entry->hnsw_ef_search << "\n";
  out << "ivf_nlist=" << entry->ivf_nlist << "\n";
  out << "ivf_nprobe=" << entry->ivf_nprobe << "\n";
  out << "ivfpq_m=" << entry->ivfpq_m << "\n";
  out << "ivfpq_bits=" << entry->ivfpq_bits << "\n";
  out << "gpu_device=" << entry->gpu_device << "\n";

  out.close();
}

static std::unordered_map<std::string, std::string> read_metadata_file(const char* path) {
  std::unordered_map<std::string, std::string> data;
  std::ifstream in(std::string(path) + ".meta");
  std::string line;

  if (!in.is_open()) return data;

  while (std::getline(in, line)) {
    size_t pos = line.find('=');

    if (pos == std::string::npos) continue;

    data[line.substr(0, pos)] = line.substr(pos + 1);
  }

  return data;
}

static inline int parse_metric(const char* metric) {
  if (pg_strcasecmp(metric, "l2") == 0) return PG_FAISS_METRIC_L2;
  if (pg_strcasecmp(metric, "ip") == 0 || pg_strcasecmp(metric, "inner_product") == 0)
    return PG_FAISS_METRIC_IP;
  if (pg_strcasecmp(metric, "cosine") == 0) return PG_FAISS_METRIC_COSINE;

  ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("unknown metric: %s", metric)));

  return PG_FAISS_METRIC_L2;
}

static inline int parse_index_type(const char* index_type) {
  if (pg_strcasecmp(index_type, "hnsw") == 0) return PG_FAISS_INDEX_HNSW;
  if (pg_strcasecmp(index_type, "ivfflat") == 0 || pg_strcasecmp(index_type, "ivf_flat") == 0)
    return PG_FAISS_INDEX_IVF_FLAT;
  if (pg_strcasecmp(index_type, "ivfpq") == 0 || pg_strcasecmp(index_type, "ivf_pq") == 0)
    return PG_FAISS_INDEX_IVF_PQ;

  ereport(ERROR,
          (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("unknown index_type: %s", index_type)));

  return PG_FAISS_INDEX_HNSW;
}

static inline int parse_device(const char* device) {
  if (pg_strcasecmp(device, "cpu") == 0) return PG_FAISS_DEVICE_CPU;
  if (pg_strcasecmp(device, "gpu") == 0) return PG_FAISS_DEVICE_GPU;

  ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("unknown device: %s", device)));

  return PG_FAISS_DEVICE_CPU;
}

static faiss::Index* build_index(const PgFaissIndexEntry* entry) {
  faiss::MetricType metric = to_faiss_metric(entry->metric);
  faiss::Index* base = NULL;

  if (entry->index_type == PG_FAISS_INDEX_HNSW) {
    faiss::IndexHNSWFlat* index = new faiss::IndexHNSWFlat(entry->dim, entry->hnsw_m, metric);
    index->hnsw.efConstruction = entry->hnsw_ef_construction;
    index->hnsw.efSearch = entry->hnsw_ef_search;
    base = index;
  } else if (entry->index_type == PG_FAISS_INDEX_IVF_FLAT) {
    faiss::IndexFlat* quantizer = new faiss::IndexFlat(entry->dim, metric);
    faiss::IndexIVFFlat* index =
        new faiss::IndexIVFFlat(quantizer, entry->dim, entry->ivf_nlist, metric);
    index->own_fields = true;
    index->nprobe = entry->ivf_nprobe;
    base = index;
  } else {
    faiss::IndexFlat* quantizer = new faiss::IndexFlat(entry->dim, metric);
    faiss::IndexIVFPQ* index = new faiss::IndexIVFPQ(quantizer, entry->dim, entry->ivf_nlist,
                                                     entry->ivfpq_m, entry->ivfpq_bits, metric);
    index->own_fields = true;
    index->nprobe = entry->ivf_nprobe;
    base = index;
  }

  return new faiss::IndexIDMap2(base);
}

extern "C" Datum pg_faiss_index_create(PG_FUNCTION_ARGS) {
  text* name_text = PG_GETARG_TEXT_PP(0);
  int32 dim = PG_GETARG_INT32(1);
  text* metric_text = PG_GETARG_TEXT_PP(2);
  text* index_type_text = PG_GETARG_TEXT_PP(3);
  Jsonb* options = PG_GETARG_JSONB_P(4);
  text* device_text = PG_GETARG_TEXT_PP(5);

  char* name = text_to_cstring(name_text);
  char* metric = text_to_cstring(metric_text);
  char* index_type = text_to_cstring(index_type_text);
  char* device = text_to_cstring(device_text);
  bool found = false;
  PgFaissIndexEntry* entry;

  if (dim < 1 || dim > PG_FAISS_MAX_DIMENSIONS)
    ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("dim must be in range 1..%d", PG_FAISS_MAX_DIMENSIONS)));

  if (strlen(name) >= PG_FAISS_MAX_INDEX_NAME)
    ereport(ERROR, (errcode(ERRCODE_NAME_TOO_LONG),
                    errmsg("index name too long (max %d)", PG_FAISS_MAX_INDEX_NAME - 1)));

  ensure_registry();

  entry = (PgFaissIndexEntry*)hash_search(pg_faiss_registry, name, HASH_ENTER, &found);

  if (found)
    ereport(ERROR,
            (errcode(ERRCODE_DUPLICATE_OBJECT), errmsg("index \"%s\" already exists", name)));

  memset(entry, 0, sizeof(PgFaissIndexEntry));
  strlcpy(entry->name, name, sizeof(entry->name));
  entry->dim = dim;
  entry->metric = parse_metric(metric);
  entry->index_type = parse_index_type(index_type);
  entry->device = parse_device(device);
#ifndef USE_FAISS_GPU
  if (entry->device == PG_FAISS_DEVICE_GPU)
    ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                    errmsg("pg_faiss was built without GPU support")));
#endif

  entry->hnsw_m = jsonb_option_int32(options, "m", PG_FAISS_DEFAULT_HNSW_M, 2, 256);
  entry->hnsw_ef_construction = jsonb_option_int32(
      options, "ef_construction", PG_FAISS_DEFAULT_HNSW_EF_CONSTRUCTION, 4, 1000000);
  entry->hnsw_ef_search =
      jsonb_option_int32(options, "ef_search", PG_FAISS_DEFAULT_HNSW_EF_SEARCH, 1, 1000000);
  entry->ivf_nlist = jsonb_option_int32(options, "nlist", PG_FAISS_DEFAULT_IVF_NLIST, 1, 1000000);
  entry->ivf_nprobe =
      jsonb_option_int32(options, "nprobe", PG_FAISS_DEFAULT_IVF_NPROBE, 1, 1000000);
  entry->ivfpq_m = jsonb_option_int32(options, "pq_m", PG_FAISS_DEFAULT_IVFPQ_M, 1, 4096);
  entry->ivfpq_bits = jsonb_option_int32(options, "pq_bits", PG_FAISS_DEFAULT_IVFPQ_BITS, 1, 16);
  entry->gpu_device = jsonb_option_int32(options, "gpu_device", 0, 0, 128);

  try {
    entry->cpu_index = build_index(entry);
    entry->is_trained = (entry->index_type == PG_FAISS_INDEX_HNSW);
    entry->num_vectors = 0;

#ifdef USE_FAISS_GPU
    if (entry->device == PG_FAISS_DEVICE_GPU) rebuild_gpu_index(entry);
#endif
  } catch (const std::exception& e) {
    hash_search(pg_faiss_registry, name, HASH_REMOVE, NULL);
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS create error: %s", e.what())));
  }

  pfree(name);
  pfree(metric);
  pfree(index_type);
  pfree(device);

  PG_RETURN_VOID();
}

extern "C" Datum pg_faiss_index_train(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  ArrayType* vectors_arr = PG_GETARG_ARRAYTYPE_P(1);
  PgFaissIndexEntry* entry = lookup_entry(name);
  std::vector<float> vectors;
  int64 n = 0;

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  read_vector_array(vectors_arr, entry->dim, vectors, &n);

  if (entry->metric == PG_FAISS_METRIC_COSINE) normalize_many(vectors.data(), n, entry->dim);

  try {
    faiss::Index* index = active_index(entry);
    index->train(n, vectors.data());
    entry->is_trained = index->is_trained;
    entry->num_vectors = index->ntotal;
#ifdef USE_FAISS_GPU
    if (entry->device == PG_FAISS_DEVICE_GPU) sync_gpu_to_cpu(entry);
#endif
  } catch (const std::exception& e) {
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS train error: %s", e.what())));
  }

  pfree(name);
  PG_RETURN_VOID();
}

extern "C" Datum pg_faiss_index_add(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  ArrayType* ids_arr = PG_GETARG_ARRAYTYPE_P(1);
  ArrayType* vectors_arr = PG_GETARG_ARRAYTYPE_P(2);
  PgFaissIndexEntry* entry = lookup_entry(name);
  std::vector<faiss::idx_t> ids;
  std::vector<float> vectors;
  int64 n = 0;

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  read_ids_array(ids_arr, ids);
  read_vector_array(vectors_arr, entry->dim, vectors, &n);

  if ((int64)ids.size() != n)
    ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("ids count (%lld) and vectors count (%lld) must match",
                           (long long)ids.size(), (long long)n)));

  if (entry->metric == PG_FAISS_METRIC_COSINE) normalize_many(vectors.data(), n, entry->dim);

  try {
    faiss::Index* index = active_index(entry);
    faiss::IndexIDMap2* idmap = dynamic_cast<faiss::IndexIDMap2*>(index);

    if (idmap == NULL)
      ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                      errmsg("internal index is not an ID map")));

    if (!index->is_trained)
      ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                      errmsg("index \"%s\" is not trained", name)));

    idmap->add_with_ids(n, vectors.data(), ids.data());
    entry->num_vectors = index->ntotal;
#ifdef USE_FAISS_GPU
    if (entry->device == PG_FAISS_DEVICE_GPU) sync_gpu_to_cpu(entry);
#endif
  } catch (const std::exception& e) {
    ereport(ERROR,
            (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION), errmsg("FAISS add error: %s", e.what())));
  }

  pfree(name);
  PG_RETURN_INT64(n);
}

extern "C" Datum pg_faiss_index_search(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  PgVector* query = datum_to_pgvector(PG_GETARG_DATUM(1));
  int32 k = PG_GETARG_INT32(2);
  Jsonb* search_params = PG_GETARG_JSONB_P(3);
  PgFaissIndexEntry* entry = lookup_entry(name);
  ReturnSetInfo* rsinfo;
  Tuplestorestate* tupstore;
  TupleDesc tupdesc;

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  if (query->dim != entry->dim)
    ereport(ERROR,
            (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
             errmsg("query dimension mismatch: expected %d, got %d", entry->dim, query->dim)));

  if (k <= 0) ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("k must be > 0")));

  materialize_result_begin(fcinfo, &tupstore, &tupdesc, &rsinfo);

  try {
    faiss::Index* index = active_index(entry);
    int32 effective_k = std::min<int64>(k, index->ntotal);

    if (effective_k > 0) {
      std::vector<float> query_buf(entry->dim);
      std::vector<float> distances(effective_k);
      std::vector<faiss::idx_t> labels(effective_k);
      int old_ef_search = 0;
      int old_nprobe = 0;
      bool changed_ef_search = false;
      bool changed_nprobe = false;

      memcpy(query_buf.data(), query->x, sizeof(float) * entry->dim);

      if (entry->metric == PG_FAISS_METRIC_COSINE) normalize_one(query_buf.data(), entry->dim);

      apply_search_params(entry, index, search_params, &old_ef_search, &old_nprobe,
                          &changed_ef_search, &changed_nprobe);

      index->search(1, query_buf.data(), effective_k, distances.data(), labels.data());

      restore_search_params(index, old_ef_search, old_nprobe, changed_ef_search, changed_nprobe);

      for (int i = 0; i < effective_k; i++) {
        Datum values[2];
        bool nulls[2] = {false, false};
        float distance = distances[i];

        if (labels[i] < 0) continue;

        if (entry->metric == PG_FAISS_METRIC_COSINE) distance = 1.0f - distance;

        values[0] = Int64GetDatum((int64)labels[i]);
        values[1] = Float4GetDatum(distance);

        tuplestore_putvalues(tupstore, tupdesc, values, nulls);
      }
    }
  } catch (const std::exception& e) {
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS search error: %s", e.what())));
  }

  materialize_result_end(rsinfo, tupstore, tupdesc);

  pfree(name);
  PG_RETURN_NULL();
}

extern "C" Datum pg_faiss_index_search_batch(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  ArrayType* queries_arr = PG_GETARG_ARRAYTYPE_P(1);
  int32 k = PG_GETARG_INT32(2);
  Jsonb* search_params = PG_GETARG_JSONB_P(3);
  PgFaissIndexEntry* entry = lookup_entry(name);
  ReturnSetInfo* rsinfo;
  Tuplestorestate* tupstore;
  TupleDesc tupdesc;

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  if (k <= 0) ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("k must be > 0")));

  materialize_result_begin(fcinfo, &tupstore, &tupdesc, &rsinfo);

  try {
    std::vector<float> queries;
    int64 num_queries = 0;
    faiss::Index* index = active_index(entry);
    int32 effective_k;

    read_vector_array(queries_arr, entry->dim, queries, &num_queries);

    if (entry->metric == PG_FAISS_METRIC_COSINE)
      normalize_many(queries.data(), num_queries, entry->dim);

    effective_k = std::min<int64>(k, index->ntotal);

    if (effective_k > 0) {
      std::vector<float> distances((size_t)num_queries * (size_t)effective_k);
      std::vector<faiss::idx_t> labels((size_t)num_queries * (size_t)effective_k);
      int old_ef_search = 0;
      int old_nprobe = 0;
      bool changed_ef_search = false;
      bool changed_nprobe = false;

      apply_search_params(entry, index, search_params, &old_ef_search, &old_nprobe,
                          &changed_ef_search, &changed_nprobe);

      index->search(num_queries, queries.data(), effective_k, distances.data(), labels.data());

      restore_search_params(index, old_ef_search, old_nprobe, changed_ef_search, changed_nprobe);

      for (int64 q = 0; q < num_queries; q++) {
        for (int i = 0; i < effective_k; i++) {
          size_t off = (size_t)q * (size_t)effective_k + (size_t)i;
          Datum values[3];
          bool nulls[3] = {false, false, false};
          float distance = distances[off];

          if (labels[off] < 0) continue;

          if (entry->metric == PG_FAISS_METRIC_COSINE) distance = 1.0f - distance;

          values[0] = Int32GetDatum((int32)(q + 1));
          values[1] = Int64GetDatum((int64)labels[off]);
          values[2] = Float4GetDatum(distance);

          tuplestore_putvalues(tupstore, tupdesc, values, nulls);
        }
      }
    }
  } catch (const std::exception& e) {
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS batch search error: %s", e.what())));
  }

  materialize_result_end(rsinfo, tupstore, tupdesc);

  pfree(name);
  PG_RETURN_NULL();
}

extern "C" Datum pg_faiss_index_save(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  char* path = text_to_cstring(PG_GETARG_TEXT_PP(1));
  PgFaissIndexEntry* entry = lookup_entry(name);

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  try {
#ifdef USE_FAISS_GPU
    if (entry->device == PG_FAISS_DEVICE_GPU) sync_gpu_to_cpu(entry);
#endif

    faiss::write_index(entry->cpu_index, path);
    write_metadata_file(entry, path);
    strlcpy(entry->index_path, path, sizeof(entry->index_path));
  } catch (const std::exception& e) {
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS save error: %s", e.what())));
  }

  pfree(name);
  pfree(path);
  PG_RETURN_VOID();
}

extern "C" Datum pg_faiss_index_load(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  char* path = text_to_cstring(PG_GETARG_TEXT_PP(1));
  char* device = text_to_cstring(PG_GETARG_TEXT_PP(2));
  int parsed_device = parse_device(device);
  bool found = false;
  PgFaissIndexEntry* entry;
  std::unordered_map<std::string, std::string> meta;
  faiss::Index* loaded_index = NULL;
  faiss::Index* base_index = NULL;

#ifndef USE_FAISS_GPU
  if (parsed_device == PG_FAISS_DEVICE_GPU)
    ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                    errmsg("pg_faiss was built without GPU support")));
#endif

  ensure_registry();

  entry = (PgFaissIndexEntry*)hash_search(pg_faiss_registry, name, HASH_ENTER, &found);

  if (found)
    ereport(ERROR,
            (errcode(ERRCODE_DUPLICATE_OBJECT), errmsg("index \"%s\" already exists", name)));

  memset(entry, 0, sizeof(PgFaissIndexEntry));
  strlcpy(entry->name, name, sizeof(entry->name));

  try {
    loaded_index = faiss::read_index(path);

    if (dynamic_cast<faiss::IndexIDMap2*>(loaded_index) == NULL)
      loaded_index = new faiss::IndexIDMap2(loaded_index);

    meta = read_metadata_file(path);

    entry->cpu_index = loaded_index;
    entry->dim = loaded_index->d;
    entry->metric =
        loaded_index->metric_type == faiss::METRIC_L2 ? PG_FAISS_METRIC_L2 : PG_FAISS_METRIC_IP;
    entry->index_type = PG_FAISS_INDEX_HNSW;
    entry->device = parsed_device;
    base_index = unwrap_idmap(loaded_index);

    if (dynamic_cast<faiss::IndexHNSW*>(base_index) != NULL)
      entry->index_type = PG_FAISS_INDEX_HNSW;
    else if (dynamic_cast<faiss::IndexIVFPQ*>(base_index) != NULL)
      entry->index_type = PG_FAISS_INDEX_IVF_PQ;
    else
      entry->index_type = PG_FAISS_INDEX_IVF_FLAT;

    if (meta.find("metric") != meta.end()) entry->metric = parse_metric(meta["metric"].c_str());
    if (meta.find("index_type") != meta.end())
      entry->index_type = parse_index_type(meta["index_type"].c_str());
    if (meta.find("hnsw_m") != meta.end())
      entry->hnsw_m = std::stoi(meta["hnsw_m"]);
    else
      entry->hnsw_m = PG_FAISS_DEFAULT_HNSW_M;
    if (meta.find("hnsw_ef_construction") != meta.end())
      entry->hnsw_ef_construction = std::stoi(meta["hnsw_ef_construction"]);
    else
      entry->hnsw_ef_construction = PG_FAISS_DEFAULT_HNSW_EF_CONSTRUCTION;
    if (meta.find("hnsw_ef_search") != meta.end())
      entry->hnsw_ef_search = std::stoi(meta["hnsw_ef_search"]);
    else
      entry->hnsw_ef_search = PG_FAISS_DEFAULT_HNSW_EF_SEARCH;
    if (meta.find("ivf_nlist") != meta.end())
      entry->ivf_nlist = std::stoi(meta["ivf_nlist"]);
    else
      entry->ivf_nlist = PG_FAISS_DEFAULT_IVF_NLIST;
    if (meta.find("ivf_nprobe") != meta.end())
      entry->ivf_nprobe = std::stoi(meta["ivf_nprobe"]);
    else
      entry->ivf_nprobe = PG_FAISS_DEFAULT_IVF_NPROBE;
    if (meta.find("ivfpq_m") != meta.end())
      entry->ivfpq_m = std::stoi(meta["ivfpq_m"]);
    else
      entry->ivfpq_m = PG_FAISS_DEFAULT_IVFPQ_M;
    if (meta.find("ivfpq_bits") != meta.end())
      entry->ivfpq_bits = std::stoi(meta["ivfpq_bits"]);
    else
      entry->ivfpq_bits = PG_FAISS_DEFAULT_IVFPQ_BITS;
    if (meta.find("gpu_device") != meta.end())
      entry->gpu_device = std::stoi(meta["gpu_device"]);
    else
      entry->gpu_device = 0;

    entry->num_vectors = loaded_index->ntotal;
    entry->is_trained = loaded_index->is_trained;
    strlcpy(entry->index_path, path, sizeof(entry->index_path));

#ifdef USE_FAISS_GPU
    if (entry->device == PG_FAISS_DEVICE_GPU) rebuild_gpu_index(entry);
#endif
  } catch (const std::exception& e) {
    hash_search(pg_faiss_registry, name, HASH_REMOVE, NULL);
    ereport(ERROR, (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                    errmsg("FAISS load error: %s", e.what())));
  }

  pfree(name);
  pfree(path);
  pfree(device);
  PG_RETURN_VOID();
}

extern "C" Datum pg_faiss_index_stats(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  PgFaissIndexEntry* entry = lookup_entry(name);
  StringInfoData json;
  Datum result;

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  initStringInfo(&json);

  appendStringInfoChar(&json, '{');

  appendStringInfoString(&json, "\"name\":");
  escape_json(&json, entry->name);
  appendStringInfoString(&json, ",");

  appendStringInfo(&json, "\"version\":\"%s\",", PG_FAISS_VERSION);
  appendStringInfo(&json, "\"dim\":%d,", entry->dim);
  appendStringInfo(&json, "\"metric\":\"%s\",", metric_name(entry->metric));
  appendStringInfo(&json, "\"index_type\":\"%s\",", index_type_name(entry->index_type));
  appendStringInfo(&json, "\"device\":\"%s\",", device_name(entry->device));
  appendStringInfo(&json, "\"num_vectors\":%lld,", (long long)entry->num_vectors);
  appendStringInfo(&json, "\"is_trained\":%s,", entry->is_trained ? "true" : "false");
  appendStringInfo(&json, "\"hnsw\":{\"m\":%d,\"ef_construction\":%d,\"ef_search\":%d},",
                   entry->hnsw_m, entry->hnsw_ef_construction, entry->hnsw_ef_search);
  appendStringInfo(&json, "\"ivf\":{\"nlist\":%d,\"nprobe\":%d},", entry->ivf_nlist,
                   entry->ivf_nprobe);
  appendStringInfo(&json, "\"ivfpq\":{\"m\":%d,\"bits\":%d},", entry->ivfpq_m, entry->ivfpq_bits);
  appendStringInfo(&json, "\"index_path\":");
  escape_json(&json, entry->index_path);

  appendStringInfoChar(&json, '}');

  result = DirectFunctionCall1(jsonb_in, CStringGetDatum(json.data));

  pfree(name);

  PG_RETURN_DATUM(result);
}

extern "C" Datum pg_faiss_index_drop(PG_FUNCTION_ARGS) {
  char* name = text_to_cstring(PG_GETARG_TEXT_PP(0));
  PgFaissIndexEntry* entry;

  ensure_registry();
  entry = lookup_entry(name);

  if (entry == NULL)
    ereport(ERROR,
            (errcode(ERRCODE_UNDEFINED_OBJECT), errmsg("index \"%s\" does not exist", name)));

  free_entry_resources(entry);
  hash_search(pg_faiss_registry, name, HASH_REMOVE, NULL);

  pfree(name);
  PG_RETURN_VOID();
}

extern "C" Datum pg_faiss_reset(PG_FUNCTION_ARGS) {
  HASH_SEQ_STATUS status;
  PgFaissIndexEntry* entry;

  if (pg_faiss_registry != NULL) {
    hash_seq_init(&status, pg_faiss_registry);
    while ((entry = (PgFaissIndexEntry*)hash_seq_search(&status)) != NULL)
      free_entry_resources(entry);

    hash_destroy(pg_faiss_registry);
    pg_faiss_registry = NULL;
  }

  ensure_registry();

  PG_RETURN_VOID();
}
