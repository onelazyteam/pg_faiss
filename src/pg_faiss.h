#ifndef PG_FAISS_H
#define PG_FAISS_H

extern "C" {
#include "postgres.h"
#include "fmgr.h"
#include "utils/jsonb.h"
}

#include <faiss/Index.h>
#ifdef USE_FAISS_GPU
#include <faiss/gpu/StandardGpuResources.h>
#endif

#define PG_FAISS_VERSION "0.2.0"
#define PG_FAISS_MAX_INDEX_NAME 64
#define PG_FAISS_MAX_DIMENSIONS 65535

#define PG_FAISS_DEFAULT_HNSW_M 32
#define PG_FAISS_DEFAULT_HNSW_EF_CONSTRUCTION 200
#define PG_FAISS_DEFAULT_HNSW_EF_SEARCH 64
#define PG_FAISS_DEFAULT_IVF_NLIST 4096
#define PG_FAISS_DEFAULT_IVF_NPROBE 32
#define PG_FAISS_DEFAULT_IVFPQ_M 64
#define PG_FAISS_DEFAULT_IVFPQ_BITS 8

enum PgFaissMetricType {
  PG_FAISS_METRIC_L2 = 0,
  PG_FAISS_METRIC_IP = 1,
  PG_FAISS_METRIC_COSINE = 2
};

enum PgFaissIndexType {
  PG_FAISS_INDEX_HNSW = 0,
  PG_FAISS_INDEX_IVF_FLAT = 1,
  PG_FAISS_INDEX_IVF_PQ = 2
};

enum PgFaissDeviceType { PG_FAISS_DEVICE_CPU = 0, PG_FAISS_DEVICE_GPU = 1 };
enum PgFaissAutotuneMode {
  PG_FAISS_AUTOTUNE_BALANCED = 0,
  PG_FAISS_AUTOTUNE_LATENCY = 1,
  PG_FAISS_AUTOTUNE_RECALL = 2
};

typedef struct PgFaissIndexEntry {
  char name[PG_FAISS_MAX_INDEX_NAME];
  int32 dim;
  int32 metric;
  int32 index_type;
  int32 device;
  int32 hnsw_m;
  int32 hnsw_ef_construction;
  int32 hnsw_ef_search;
  int32 ivf_nlist;
  int32 ivf_nprobe;
  int32 ivfpq_m;
  int32 ivfpq_bits;
  int32 gpu_device;
  int32 preferred_batch_size;
  int32 last_candidate_k;
  int32 last_batch_size;
  int32 last_autotune_mode;
  bool is_trained;
  int64 num_vectors;
  int64 train_calls;
  int64 add_calls;
  int64 add_vectors_total;
  int64 search_single_calls;
  int64 search_batch_calls;
  int64 search_filtered_calls;
  int64 search_query_total;
  int64 search_result_total;
  int64 save_calls;
  int64 load_calls;
  int64 autotune_calls;
  int64 error_calls;
  double search_single_ms_total;
  double search_batch_ms_total;
  double search_filtered_ms_total;
  char index_path[MAXPGPATH];
  faiss::Index* cpu_index;
#ifdef USE_FAISS_GPU
  faiss::gpu::StandardGpuResources* gpu_resources;
  faiss::Index* gpu_index;
#endif
} PgFaissIndexEntry;

#endif
