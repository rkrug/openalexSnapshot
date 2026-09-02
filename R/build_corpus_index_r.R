# build_corpus_index_r ---
# Pure-R/DuckDB implementation behind build_corpus_index(backend = "r").
#
# Recovered from openalexPro 70539a0:R/build_corpus_index.R (.build_one_index),
# where it was a working, validated implementation before the Rust rewrite.
# Changes from that version:
#   * `filename = true` replaces the per-file R-side relative-path computation,
#     so Stage 1 issues one statement per batch instead of one per file. This
#     also removes the Windows 8.3 short-name path-depth workaround.
#   * ZSTD instead of SNAPPY (smaller index, same read speed).
#   * Connection setup goes through .oas_con().

#' Build one ID index in pure R
#'
#' Two stages: shard per batch of files (parallel, resumable), then combine.
#'
#' @inheritParams build_corpus_index
#' @param corpus_dir Single dataset Parquet directory.
#' @return Invisibly, the path to the index file.
#' @noRd
.oas_build_one_index <- function(corpus_dir,
                                 workers = NULL,
                                 memory_limit = NULL,
                                 temp_dir = NULL,
                                 batch_bytes = 8e9,
                                 overwrite = FALSE,
                                 verbose = TRUE) {
  if (!dir.exists(corpus_dir)) {
    stop("corpus_dir does not exist: ", corpus_dir, call. = FALSE)
  }

  corpus_dir  <- normalizePath(corpus_dir)
  parent_dir  <- dirname(corpus_dir)
  corpus_name <- basename(corpus_dir)
  index_file  <- file.path(parent_dir, paste0(corpus_name, "_id_idx.parquet"))

  if (file.exists(index_file)) {
    if (!isTRUE(overwrite)) {
      message("index_file exists - creation skipped",
              " - delete manually or use overwrite = TRUE to re-create: ",
              index_file)
      return(invisible(index_file))
    }
    unlink(index_file)
  }

  files <- .oas_corpus_files(corpus_dir)
  if (is.null(temp_dir)) temp_dir <- paste0(index_file, "_tmp")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(temp_dir, ".metadata_never_index"))

  batches <- .oas_plan_batches(files, batch_bytes = batch_bytes)
  total_start <- Sys.time()

  if (isTRUE(verbose)) {
    message("Building index from: ", corpus_dir)
    message("    Writing to: ", index_file)
    message("Stage 1: ", length(files), " parquet files in ",
            length(batches), " batches",
            if (!is.null(workers) && workers > 1L) {
              paste0(" with ", workers, " workers...")
            } else " sequentially...")
  }

  if (!is.null(workers) && workers > 1L) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  root_prefix <- paste0(.oas_fwd(parent_dir), "/")

  progressr::with_progress(
    {
      p <- progressr::progressor(along = batches)
      future.apply::future_lapply(seq_along(batches), function(i) {
        out_file <- file.path(temp_dir, sprintf("idx_%05d.parquet", i))
        if (file.exists(out_file)) {          # resume
          p()
          return(invisible(NULL))
        }
        wcon <- .oas_con(memory_limit = memory_limit, threads = 1L)
        on.exit(DBI::dbDisconnect(wcon, shutdown = TRUE), add = TRUE)

        q <- paste0(
          "COPY (SELECT ",
          "  w.id AS id, ",
          "  CAST(FLOOR(CAST(regexp_extract(w.id, '(\\d+)$', 1) AS BIGINT) / 10000)",
          "       AS INTEGER) AS id_block, ",
          "  replace(replace(w.filename, ", .oas_sql_str(root_prefix), ", ''),",
          "          '\\', '/') AS parquet_file, ",
          "  w.file_row_number AS file_row_number ",
          "FROM read_parquet(", .oas_sql_paths(batches[[i]]),
          ", filename = true, file_row_number = true, hive_partitioning = false) AS w",
          ") TO ", .oas_sql_str(.oas_fwd(out_file)),
          " (FORMAT PARQUET, COMPRESSION ZSTD)"
        )
        DBI::dbExecute(wcon, q)
        p()
        invisible(NULL)
      }, future.seed = TRUE)
    },
    handlers = progressr::handler_cli()
  )

  if (isTRUE(verbose)) message("    Stage 1 complete.")
  if (isTRUE(verbose)) message("Stage 2: combining into ", index_file)

  con <- .oas_con(memory_limit = memory_limit, temp_dir = temp_dir,
                  threads = workers, preserve_order = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, paste0(
    "COPY (SELECT * FROM read_parquet(",
    .oas_sql_str(paste0(.oas_fwd(temp_dir), "/idx_*.parquet")),
    ")) TO ", .oas_sql_str(.oas_fwd(index_file)),
    " (FORMAT PARQUET, COMPRESSION ZSTD)"
  ))

  unlink(temp_dir, recursive = TRUE)

  if (isTRUE(verbose)) {
    message("Done! Index size: ",
            round(file.info(index_file)$size / 1024^3, 3), " GB")
    message("Total time: ",
            round(difftime(Sys.time(), total_start, units = "mins"), 2),
            " minutes")
  }

  invisible(index_file)
}
