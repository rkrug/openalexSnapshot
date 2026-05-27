#' Convert OpenAlex snapshot to Parquet format
#'
#' Converts OpenAlex snapshot `.json.gz` files to Parquet using schema
#' inference and parallel conversion. Paths can be supplied as a single
#' `root_dir` (which derives `snapshot_dir` and `parquet_dir` automatically)
#' or as explicit `snapshot_dir` and `parquet_dir` arguments.
#'
#' @param root_dir Root directory. If provided, `snapshot_dir` defaults to
#'   `<root_dir>/openalex-snapshot` and `parquet_dir` defaults to
#'   `<root_dir>/parquet`.
#' @param data_sets Character vector of dataset names to convert (e.g.
#'   `c("works", "authors")`). `NULL` converts all datasets found under
#'   `<snapshot_dir>/data/`.
#' @param workers Number of parallel workers for file conversion. Default is
#'   `NULL` (sequential).
#' @param sample_size Number of `.gz` files to sample for unified schema
#'   inference. Higher values give more accurate schemas but take longer.
#'   Default is `20`. Use `NULL` or `0` to use all files.
#' @param memory_limit DuckDB memory limit per worker (e.g., `"8GB"`).
#'   Default is `NULL` (DuckDB default).
#' @param temp_directory Location of the temporary directory for DuckDB.
#'   Default is `NULL` (system default).
#' @param progress Ignored (kept for backward compatibility).
#' @param verbose Print per-dataset progress messages. Default is `TRUE`.
#' @param snapshot_dir Explicit path to the snapshot data directory (the one
#'   containing a `data/` subfolder). Required when `root_dir` is not
#'   provided.
#' @param parquet_dir Explicit path to the Parquet output directory. Required
#'   when `root_dir` is not provided.
#'
#' @return Invisibly returns `NULL`.
#'
#' @seealso [build_corpus_index()] for indexing the resulting Parquet files,
#'   [lookup_by_id()] for ID-based record retrieval.
#'
#' @examples
#' \dontrun{
#' snapshot_to_parquet(root_dir = "/Volumes/openalex")
#'
#' snapshot_to_parquet(
#'   root_dir     = "/Volumes/openalex",
#'   data_sets    = c("authors", "works"),
#'   workers      = 4,
#'   memory_limit = "8GB"
#' )
#'
#' # Explicit paths (no root_dir):
#' snapshot_to_parquet(
#'   snapshot_dir = "/data/openalex-snapshot",
#'   parquet_dir  = "/data/parquet",
#'   data_sets    = "authors"
#' )
#' }
#'
#' @export
snapshot_to_parquet <- function(
  root_dir       = NULL,
  data_sets      = NULL,
  workers        = NULL,
  sample_size    = 20,
  memory_limit   = NULL,
  temp_directory = NULL,
  progress       = TRUE,
  verbose        = TRUE,
  snapshot_dir   = NULL,
  parquet_dir    = NULL
) {
  # Resolve paths from root_dir if provided ------------------------------------
  if (!is.null(root_dir)) {
    snapshot_dir <- file.path(root_dir, "openalex-snapshot")
    parquet_dir  <- file.path(root_dir, "parquet")
  }
  if (is.null(snapshot_dir) || is.null(parquet_dir)) {
    stop(
      "Provide either `root_dir` or both `snapshot_dir` and `parquet_dir`.",
      call. = FALSE
    )
  }

  oa_snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir  = parquet_dir,
    data_sets    = if (is.null(data_sets)) character(0L) else as.character(data_sets),
    workers      = as.integer(if (is.null(workers)) 1L else workers),
    sample_size  = as.integer(if (is.null(sample_size) || sample_size == 0) 0L else sample_size),
    memory_limit = if (is.null(memory_limit)) "" else as.character(memory_limit),
    temp_dir     = if (is.null(temp_directory)) "" else as.character(temp_directory),
    verbose      = isTRUE(verbose)
  )

  invisible(NULL)
}
