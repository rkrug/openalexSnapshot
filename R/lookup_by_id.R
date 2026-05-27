#' Look up records by OpenAlex ID
#'
#' Uses a pre-built index (created by [build_corpus_index()]) to locate records
#' efficiently and extract them from the Parquet corpus.
#'
#' Paths can be supplied as a `root_dir` + `data_sets` pair (which
#' automatically locates the correct index files and writes output into
#' `project_dir`) or as an explicit `index_file` for direct use.
#'
#' @param root_dir Root directory containing `parquet/` and the dataset indexes
#'   produced by [build_corpus_index()]. Index files are expected at
#'   `<root_dir>/parquet/<dataset>_id_idx.parquet`.
#' @param ids Character vector of OpenAlex IDs to retrieve. Can be long form
#'   (e.g. `"https://openalex.org/W2741809807"`) or short form
#'   (e.g. `"W2741809807"`).
#' @param project_dir Project output directory. Extracted Parquet files are
#'   written to `<project_dir>/snapshot_extract_<dataset>/`. Only used when
#'   `root_dir` is provided.
#' @param data_sets Character vector of dataset names to search (e.g.
#'   `c("works", "authors")`). `NULL` searches all indexed datasets under
#'   `<root_dir>/parquet/`. Ignored when `index_file` is provided.
#' @param workers Number of parallel workers for reading corpus files. Default
#'   is `NULL` (sequential).
#' @param progress Ignored (kept for backward compatibility).
#' @param verbose Print progress messages. Default is `TRUE`.
#' @param index_file Explicit path to an index Parquet file created by
#'   [build_corpus_index()]. When provided, `root_dir`, `data_sets`, and
#'   `project_dir` are ignored.
#' @param selected Column selection passed to `arrow::open_dataset()`. Default
#'   is `NULL` (all columns).
#' @param output Path to an output directory for writing results as Parquet
#'   files when using `index_file` mode. If `NULL` (default), results are
#'   returned as a data frame. Ignored when `root_dir` is used (use
#'   `project_dir` instead).
#'
#' @return
#' * `index_file` mode, `output` not `NULL`: invisibly returns `output`.
#' * `index_file` mode, `output` is `NULL`: returns a data frame of matching
#'   records.
#' * `root_dir` mode: invisibly returns `project_dir`.
#'
#' @seealso [build_corpus_index()] for building the required index,
#'   [snapshot_to_parquet()] for creating the Parquet corpus.
#'
#' @importFrom arrow open_dataset
#' @importFrom dplyr collect
#'
#' @examples
#' \dontrun{
#' # root_dir mode (searches multiple datasets)
#' lookup_by_id(
#'   root_dir    = "/Volumes/openalex",
#'   ids         = c("W2741809807", "W1234567890"),
#'   project_dir = "my_project",
#'   data_sets   = "works"
#' )
#'
#' # index_file mode (direct access, returns data frame)
#' records <- lookup_by_id(
#'   index_file = "works_id_index.parquet",
#'   ids        = c("W2741809807", "W1234567890")
#' )
#'
#' # index_file mode (write to parquet)
#' lookup_by_id(
#'   index_file = "works_id_index.parquet",
#'   ids        = large_id_vector,
#'   output     = "filtered_works",
#'   workers    = 3
#' )
#' }
#'
#' @export
lookup_by_id <- function(
  root_dir    = NULL,
  ids,
  project_dir = NULL,
  data_sets   = NULL,
  workers     = NULL,
  progress    = TRUE,
  verbose     = TRUE,
  index_file  = NULL,
  selected    = NULL,
  output      = NULL
) {
  if (missing(ids) || length(ids) == 0L) {
    stop("'ids' must be provided and non-empty.", call. = FALSE)
  }

  workers_int <- as.integer(if (is.null(workers)) 1L else workers)

  # index_file mode ------------------------------------------------------------
  if (!is.null(index_file)) {
    if (is.null(output)) {
      # Write to a temp dir, read back as data frame, then clean up.
      tmp_out <- tempfile(pattern = "oa_lookup_")
      on.exit(unlink(tmp_out, recursive = TRUE, force = TRUE), add = TRUE)
      oa_lookup_by_id(
        index_file = index_file,
        ids        = as.character(ids),
        output     = tmp_out,
        workers    = workers_int,
        verbose    = isTRUE(verbose)
      )
      pq_files <- list.files(tmp_out, pattern = "\\.parquet$",
                             full.names = TRUE, recursive = TRUE)
      if (length(pq_files) == 0L) {
        message("No matching records found.")
        return(data.frame())
      }
      result <- arrow::open_dataset(tmp_out) |> dplyr::collect()
      if ("file_row_number" %in% names(result)) {
        result$file_row_number <- NULL
      }
      message("Retrieved ", nrow(result), " records")
      return(result)
    } else {
      oa_lookup_by_id(
        index_file = index_file,
        ids        = as.character(ids),
        output     = output,
        workers    = workers_int,
        verbose    = isTRUE(verbose)
      )
      return(invisible(output))
    }
  }

  # root_dir mode --------------------------------------------------------------
  if (is.null(root_dir)) {
    stop(
      "Provide either `root_dir` or `index_file`.",
      call. = FALSE
    )
  }

  parquet_root <- file.path(root_dir, "parquet")

  if (is.null(data_sets)) {
    idx_files <- list.files(
      parquet_root,
      pattern   = "_id_idx\\.parquet$",
      full.names = FALSE,
      recursive  = FALSE
    )
    data_sets <- sub("_id_idx\\.parquet$", "", idx_files)
  }

  if (length(data_sets) == 0L) {
    stop(
      "No index files found under ", parquet_root,
      ". Run build_corpus_index() first.",
      call. = FALSE
    )
  }

  if (!is.null(project_dir)) {
    dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  }

  for (ds in data_sets) {
    idx_path <- file.path(parquet_root, paste0(ds, "_id_idx.parquet"))
    if (!file.exists(idx_path)) {
      if (isTRUE(verbose)) message("No index for dataset '", ds, "', skipping.")
      next
    }

    ds_output <- if (!is.null(project_dir)) {
      file.path(project_dir, paste0("snapshot_extract_", ds))
    } else {
      stop("project_dir must be provided in root_dir mode.", call. = FALSE)
    }

    oa_lookup_by_id(
      index_file = idx_path,
      ids        = as.character(ids),
      output     = ds_output,
      workers    = workers_int,
      verbose    = isTRUE(verbose)
    )
  }

  invisible(project_dir)
}
