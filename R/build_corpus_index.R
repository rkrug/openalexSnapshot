#' Build a Parquet ID-lookup index
#'
#' Builds a `<dataset>_id_idx.parquet` index from the Parquet corpus produced
#' by [snapshot_to_parquet()], enabling fast record retrieval by OpenAlex ID
#' using [lookup_by_id()].
#'
#' The function uses a two-stage approach:
#' 1. Index each Parquet file individually (bounded memory, parallel, with
#'    resume support).
#' 2. Combine the per-file shard indexes into a single Parquet index.
#'
#' Paths can be supplied as a single `root_dir` (which iterates over all
#' requested `data_sets`) or as an explicit `corpus_dir` pointing to a single
#' dataset directory.
#'
#' @param root_dir Root directory containing a `parquet/` subdirectory produced
#'   by [snapshot_to_parquet()]. If provided, the index for each dataset in
#'   `data_sets` is created at `<root_dir>/parquet/<dataset>_id_idx.parquet`.
#' @param data_sets Character vector of dataset names to index (e.g.
#'   `c("works", "authors")`). `NULL` indexes all datasets found under
#'   `<root_dir>/parquet/`. Ignored when `corpus_dir` is provided.
#' @param workers Number of parallel workers for Stage 1 indexing. Default is
#'   `NULL` (sequential).
#' @param memory_limit DuckDB memory limit (e.g., `"20GB"`). Default is `NULL`.
#' @param temp_dir Directory for Stage-1 shards and DuckDB spill. Defaults to a
#'   subdirectory of [tempdir()], which is on local disk.
#'
#'   The default matters. Spilling beside the index puts those writes on the
#'   same device the corpus is being read from, and on an external USB SSD that
#'   measured **8.18 s/batch versus 0.76 s/batch** -- a 10.8x difference from
#'   this setting alone. Override it only to point at a *different* fast disk,
#'   or if the default lacks room: peak usage is roughly the size of the
#'   finished index plus its transient shards.
#' @param batch_bytes Approximate bytes of source parquet per Stage-1 batch.
#' @param overwrite If `TRUE`, rebuilds existing indexes. Default is `FALSE`
#'   (skip if the index already exists).
#' @param verbose Print progress messages. Default is `TRUE`.
#' @param corpus_dir Explicit path to a single dataset Parquet directory (e.g.
#'   `"/Volumes/openalex/parquet/works"`). The index is written as a sibling
#'   file: `<parent>/<basename>_id_idx.parquet`. When this is provided,
#'   `root_dir` and `data_sets` are ignored.
#' @param backend Retained only so that existing calls passing
#'   `backend = "rust"` get an explanatory error. The compiled backend was
#'   removed in 0.1.0; the package is pure R. `"auto"` (the default) and
#'   `"r"` both use the pure-R/DuckDB implementation. `"rust"` uses the
#'   compiled library and is **deprecated**: it writes an unsorted index and
#'   supports neither `columns` nor `add_columns`. It will be removed in a
#'   future release. `snapshot_to_parquet()` is unaffected and remains
#'   Rust-only. `"auto"` (the default) uses the
#'   compiled Rust library when it is loaded and the pure-R/DuckDB
#'   implementation otherwise, so behaviour is unchanged for an installed
#'   binary. `"r"` forces pure R and is always available. `"rust"` forces the
#'   compiled path and errors if it is not loaded.
#'
#' @return When `corpus_dir` is provided, invisibly returns the path to the
#'   created index file. When `root_dir` is used, invisibly returns `root_dir`.
#'
#' @details The index contains columns:
#' \describe{
#'   \item{id}{The OpenAlex ID}
#'   \item{id_block}{Block number computed as `floor(numeric_id / 10000)`}
#'   \item{parquet_file}{Relative path to the Parquet file in the corpus}
#'   \item{file_row_number}{Row number within the file (0-indexed)}
#' }
#'
#' @seealso [snapshot_to_parquet()] for creating the Parquet corpus,
#'   [lookup_by_id()] for ID-based record retrieval.
#'
#' @examples
#' \dontrun{
#' build_corpus_index(root_dir = "/Volumes/openalex")
#'
#' build_corpus_index(
#'   root_dir  = "/Volumes/openalex",
#'   data_sets = "works",
#'   workers   = 4
#' )
#'
#' # Single explicit directory:
#' build_corpus_index(
#'   corpus_dir   = "/Volumes/openalex/parquet/works",
#'   memory_limit = "20GB"
#' )
#' }
#'
#' @export
build_corpus_index <- function(
  root_dir     = NULL,
  data_sets    = NULL,
  workers      = NULL,
  memory_limit = NULL,
  temp_dir     = NULL,
  batch_bytes  = 1e9,
  overwrite    = FALSE,
  verbose      = TRUE,
  corpus_dir   = NULL,
  backend      = c("auto", "r", "rust")
) {
  backend          <- .oas_backend(backend)

  build_one <- function(dir) {
    .oas_build_one_index(
      corpus_dir   = dir,
      workers      = workers,
      memory_limit = memory_limit,
      temp_dir     = temp_dir,
      batch_bytes  = batch_bytes,
      overwrite    = isTRUE(overwrite),
      verbose      = isTRUE(verbose)
    )
  }

  # corpus_dir mode: index a single explicit directory -------------------------
  if (!is.null(corpus_dir)) {
    return(invisible(build_one(corpus_dir)))
  }

  # root_dir mode: iterate over datasets ---------------------------------------
  if (is.null(root_dir)) {
    stop(
      "Provide either `root_dir` or `corpus_dir`.",
      call. = FALSE
    )
  }

  parquet_root <- .oas_parquet_root(root_dir)

  if (is.null(data_sets)) {
    data_sets <- list.dirs(parquet_root, recursive = FALSE, full.names = FALSE)
    data_sets <- data_sets[!grepl("^\\.", data_sets)]
  }

  for (ds in data_sets) {
    build_one(file.path(parquet_root, ds))
  }

  invisible(root_dir)
}
