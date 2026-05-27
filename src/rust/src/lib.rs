use extendr_api::prelude::*;

// ── Snapshot conversion pipeline ─────────────────────────────────────────────

/// Convert an OpenAlex snapshot to Parquet format.
///
/// Full pipeline: schema inference (per-dataset, cached in
/// `<parquet_dir>/<dataset>/.schema_cache/unified_schema.csv`) plus parallel
/// per-file COPY via rayon.
///
/// @param snapshot_dir Path to the snapshot root (contains a `data/` subdir).
/// @param parquet_dir  Output directory for Parquet files.
/// @param data_sets    Character vector of dataset names, or `character(0)` for
///   all datasets found under `snapshot_dir/data/` (excluding `merged_ids`).
/// @param workers      Number of parallel workers (`1` = sequential).
/// @param sample_size  Files to sample for schema inference (`0` = all).
/// @param memory_limit DuckDB memory limit, e.g. `"8GB"` (`""` = no limit).
/// @param temp_dir     DuckDB temp directory (`""` = system default).
/// @param verbose      Print progress to stderr.
/// @return Invisibly returns `NULL`.
/// @export
#[extendr]
fn oa_snapshot_to_parquet(
    snapshot_dir: &str,
    parquet_dir: &str,
    data_sets: Vec<String>,
    workers: i32,
    sample_size: i32,
    memory_limit: &str,
    temp_dir: &str,
    verbose: bool,
) -> extendr_api::Result<()> {
    openalex_core::conversion::snapshot_to_parquet(
        snapshot_dir,
        parquet_dir,
        data_sets,
        workers.max(1) as usize,
        sample_size.max(0) as usize,
        memory_limit,
        temp_dir,
        verbose,
    )
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

/// Build a two-stage ID-lookup index for a single Parquet corpus directory.
///
/// Stage 1: per-file shard indexes (parallel via rayon).
/// Stage 2: combine shards into `<corpus_name>_id_idx.parquet`.
///
/// Returns the path to the created index file as a character scalar.
///
/// @param corpus_dir   Path to a single dataset Parquet directory.
/// @param workers      Number of parallel workers for Stage 1.
/// @param memory_limit DuckDB memory limit (`""` = no limit).
/// @param overwrite    If `TRUE`, rebuild an existing index.
/// @param verbose      Print progress to stderr.
/// @return Character scalar: path to the index file.
/// @export
#[extendr]
fn oa_build_corpus_index(
    corpus_dir: &str,
    workers: i32,
    memory_limit: &str,
    overwrite: bool,
    verbose: bool,
) -> extendr_api::Result<String> {
    openalex_core::conversion::build_corpus_index(
        corpus_dir,
        workers.max(1) as usize,
        memory_limit,
        overwrite,
        verbose,
    )
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

/// Look up records by OpenAlex ID using a pre-built index.
///
/// Reads the index file, filters to the requested IDs, and extracts matching
/// rows into the `output` directory (which must not already exist).
///
/// @param index_file Path to the index Parquet file (created by
///   [oa_build_corpus_index()]).
/// @param ids        Character vector of OpenAlex IDs (long or short form).
/// @param output     Output directory path. Must not already exist.
/// @param workers    Number of parallel workers for file extraction.
/// @param verbose    Print progress to stderr.
/// @return Invisibly returns `NULL`.
/// @export
#[extendr]
fn oa_lookup_by_id(
    index_file: &str,
    ids: Vec<String>,
    output: &str,
    workers: i32,
    verbose: bool,
) -> extendr_api::Result<()> {
    openalex_core::conversion::lookup_by_id(
        index_file,
        &ids,
        output,
        workers.max(1) as usize,
        verbose,
    )
    .map(|_| ())
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

// ── Module registration ───────────────────────────────────────────────────────

extendr_module! {
    mod openalex_snapshot;
    fn oa_snapshot_to_parquet;
    fn oa_build_corpus_index;
    fn oa_lookup_by_id;
}
