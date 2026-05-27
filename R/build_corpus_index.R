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
#' @param overwrite If `TRUE`, rebuilds existing indexes. Default is `FALSE`
#'   (skip if the index already exists).
#' @param verbose Print progress messages. Default is `TRUE`.
#' @param corpus_dir Explicit path to a single dataset Parquet directory (e.g.
#'   `"/Volumes/openalex/parquet/works"`). The index is written as a sibling
#'   file: `<parent>/<basename>_id_idx.parquet`. When this is provided,
#'   `root_dir` and `data_sets` are ignored.
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
  overwrite    = FALSE,
  verbose      = TRUE,
  corpus_dir   = NULL
) {
  stop(
    "build_corpus_index() is not yet implemented in openalexSnapshot.\n",
    "The Rust back-end (openalex-core via extendr) has not been wired up yet.\n",
    "A pure-R/DuckDB fallback is planned — contributions welcome.",
    call. = FALSE
  )
}
