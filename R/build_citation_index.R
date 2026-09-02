#' Build an inverted citation index
#'
#' Inverts the `referenced_works` column of the works corpus into an edge set
#' keyed by the **cited** work, so that "which works cite X?" becomes a point
#' lookup instead of a full-corpus scan. This is what makes [get_citing()]
#' possible offline: the snapshot's `cited_by_api_url` is a URL and useless
#' without network access, but the citing direction is recoverable by
#' inverting the references every work already carries.
#'
#' [get_cited()] does **not** need this index -- the works a paper references
#' are simply its own `referenced_works` -- so only one index is built, not a
#' pair.
#'
#' @section Layout:
#' Unlike `<dataset>_id_idx.parquet` and `<dataset>_doi_idx.parquet`, which are
#' single files, this index is a **hive-partitioned directory**:
#'
#' ```
#' works_cite_idx/
#'   _index_meta.parquet
#'   cited_block=0/part-0.parquet
#'   cited_block=1/part-0.parquet
#'   ...
#' ```
#'
#' The reason is scale. The full OpenAlex works corpus holds roughly three
#' billion reference edges; a single sorted file would need a global sort of
#' that many rows, and its footer alone would cost tens of megabytes to parse
#' on every query. Partitioning by a coarse block of the cited ID keeps each
#' part small enough to sort in memory and lets a lookup open only the handful
#' of parts it needs.
#'
#' `_index_meta.parquet` is written **last**; its presence is what marks the
#' index complete, and it records the `block_size` the query side must use.
#'
#' @param root_dir Root directory containing a `parquet/` subdirectory, or the
#'   parquet directory itself.
#' @param data_sets Datasets to index. Only works carry `referenced_works`, so
#'   the default is `"works"`.
#' @param workers Number of parallel workers.
#' @param memory_limit DuckDB memory limit per worker, e.g. `"8GB"`.
#' @param temp_dir Directory for Stage-1 shards and DuckDB spill. Defaults to a
#'   sibling of the index. Peak transient usage is roughly the size of the
#'   finished index.
#' @param block_size Width of a `cited_block`. The default `1e7` yields ~351
#'   partitions over the full corpus, averaging tens of MB each. Do **not** use
#'   the ID index's `floor(n / 1e4)`: the largest OpenAlex work ID would give
#'   over 700,000 partitions.
#' @param batch_bytes Approximate bytes of source parquet per Stage-1 batch.
#'   Batching is by byte budget over the flat file list rather than by hive
#'   partition, because the corpus is extremely skewed -- one `updated_date=`
#'   partition can hold half the works while hundreds hold megabytes.
#' @param compression Parquet compression codec.
#' @param overwrite Rebuild an existing index.
#' @param verbose Print progress.
#' @param corpus_dir Explicit path to a single dataset Parquet directory.
#'
#' @return Invisibly, the path to the index directory (`corpus_dir` mode) or
#'   `root_dir`.
#'
#' @details Each part file holds:
#' \describe{
#'   \item{cited_id}{Numeric part of the cited work's ID, as `UBIGINT`}
#'   \item{citing_id}{Numeric part of the citing work's ID, as `UBIGINT`}
#' }
#' sorted by `(cited_id, citing_id)`. IDs are stored numerically rather than as
#' URLs: at three billion rows the `https://openalex.org/W` prefix would
#' dominate the index. Measured on the real corpus this costs about 5 bytes per
#' edge.
#'
#' @seealso [get_citing()], [get_cited()]
#' @export
build_citation_index <- function(root_dir = NULL,
                                 data_sets = "works",
                                 workers = NULL,
                                 memory_limit = NULL,
                                 temp_dir = NULL,
                                 block_size = 1e7,
                                 batch_bytes = 8e9,
                                 compression = "zstd",
                                 overwrite = FALSE,
                                 verbose = TRUE,
                                 corpus_dir = NULL) {
  build_one <- function(dir) {
    .oas_build_one_citation_index(
      corpus_dir = dir, workers = workers, memory_limit = memory_limit,
      temp_dir = temp_dir, block_size = block_size, batch_bytes = batch_bytes,
      compression = compression, overwrite = overwrite, verbose = verbose
    )
  }

  if (!is.null(corpus_dir)) return(invisible(build_one(corpus_dir)))
  if (is.null(root_dir)) {
    stop("Provide either `root_dir` or `corpus_dir`.", call. = FALSE)
  }
  parquet_root <- .oas_parquet_root(root_dir)
  for (ds in data_sets) build_one(file.path(parquet_root, ds))
  invisible(root_dir)
}

#' @noRd
.oas_build_one_citation_index <- function(corpus_dir,
                                          workers = NULL,
                                          memory_limit = NULL,
                                          temp_dir = NULL,
                                          block_size = 1e7,
                                          batch_bytes = 8e9,
                                          compression = "zstd",
                                          overwrite = FALSE,
                                          verbose = TRUE) {
  if (!dir.exists(corpus_dir)) {
    stop("corpus_dir does not exist: ", corpus_dir, call. = FALSE)
  }
  corpus_dir  <- normalizePath(corpus_dir)
  parent_dir  <- dirname(corpus_dir)
  corpus_name <- basename(corpus_dir)
  index_dir   <- file.path(parent_dir, paste0(corpus_name, "_cite_idx"))
  block_size  <- as.integer(block_size)
  comp        <- toupper(compression)

  complete <- file.exists(file.path(index_dir, "_index_meta.parquet"))
  if (dir.exists(index_dir) && complete && !isTRUE(overwrite)) {
    message("index exists - creation skipped",
            " - delete manually or use overwrite = TRUE to re-create: ",
            index_dir)
    return(invisible(index_dir))
  }
  if (isTRUE(overwrite)) unlink(index_dir, recursive = TRUE)

  files <- .oas_corpus_files(corpus_dir)
  if (is.null(temp_dir)) temp_dir <- paste0(index_dir, "_tmp")
  shards_dir <- file.path(temp_dir, "shards")
  done_dir   <- file.path(temp_dir, ".done")
  dir.create(shards_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(done_dir,   recursive = TRUE, showWarnings = FALSE)

  sniff_con <- .oas_con()
  refs <- tryCatch(.oas_refs_expr(sniff_con, files, alias = "w"),
                   finally = DBI::dbDisconnect(sniff_con, shutdown = TRUE))

  batches <- .oas_plan_batches(files, batch_bytes = batch_bytes)
  total_start <- Sys.time()

  if (isTRUE(verbose)) {
    message("Building citation index from: ", corpus_dir)
    message("    Writing to: ", index_dir)
    message("    referenced_works encoding: ", refs$enc)
    message("Stage 1: ", length(files), " files in ", length(batches),
            " batches, block_size = ", format(block_size, scientific = FALSE))
  }

  if (!is.null(workers) && workers > 1L) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  # Stage 1: extract edges, range-partition by cited_block ---------------------
  progressr::with_progress(
    {
      p <- progressr::progressor(along = batches)
      future.apply::future_lapply(seq_along(batches), function(i) {
        tag    <- sprintf("b%05d", i)
        marker <- file.path(done_dir, tag)
        if (file.exists(marker)) {          # resume
          p()
          return(invisible(NULL))
        }
        # A partitioned COPY writes many files, so file existence is not a
        # completion marker. Clear any partial output from an interrupted run;
        # FILENAME_PATTERN is what makes those files identifiable (and what
        # makes concurrent writes into one shard tree safe).
        partial <- list.files(shards_dir, pattern = paste0("^", tag, "_"),
                              recursive = TRUE, full.names = TRUE)
        if (length(partial)) unlink(partial)

        wcon <- .oas_con(memory_limit = memory_limit, temp_dir = temp_dir,
                         threads = 1L, preserve_order = FALSE)
        on.exit(DBI::dbDisconnect(wcon, shutdown = TRUE), add = TRUE)
        # Default is 100, which is below the partition count; leaving it there
        # makes DuckDB rotate files and emit far more shards than expected.
        DBI::dbExecute(wcon, "SET partitioned_write_max_open_files = 512")

        q <- paste0(
          "COPY (SELECT cited_id, citing_id, ",
          "  CAST(cited_id // ", block_size, " AS INTEGER) AS cited_block ",
          "FROM (SELECT ",
          "   TRY_CAST(substr(r.ref, position('/W' IN r.ref) + 2) AS UBIGINT) AS cited_id, ",
          "   TRY_CAST(substr(w.id , position('/W' IN w.id ) + 2) AS UBIGINT) AS citing_id ",
          " FROM read_parquet(", .oas_sql_paths(batches[[i]]),
          ", hive_partitioning = false) AS w, ",
          " LATERAL UNNEST(", refs$expr, ") AS r(ref) ",
          " WHERE w.referenced_works IS NOT NULL) ",
          "WHERE cited_id IS NOT NULL AND citing_id IS NOT NULL",
          ") TO ", .oas_sql_str(.oas_fwd(shards_dir)),
          " (FORMAT PARQUET, COMPRESSION ", comp,
          ", PARTITION_BY (cited_block)",
          ", FILENAME_PATTERN ", .oas_sql_str(paste0(tag, "_{i}")),
          ", OVERWRITE_OR_IGNORE, ROW_GROUP_SIZE 1000000)"
        )
        DBI::dbExecute(wcon, q)
        file.create(marker)
        p()
        invisible(NULL)
      }, future.seed = TRUE)
    },
    handlers = progressr::handler_cli()
  )

  # Stage 2: sort/merge each block. No global sort. ---------------------------
  blocks <- list.dirs(shards_dir, recursive = FALSE, full.names = FALSE)
  blocks <- blocks[grepl("^cited_block=", blocks)]
  if (length(blocks) == 0L) {
    stop("No edges were extracted; is `referenced_works` empty throughout?",
         call. = FALSE)
  }
  dir.create(index_dir, recursive = TRUE, showWarnings = FALSE)

  if (isTRUE(verbose)) {
    message("    Stage 1 complete.")
    message("Stage 2: sorting ", length(blocks), " blocks ...")
  }

  n_edges <- progressr::with_progress(
    {
      p <- progressr::progressor(along = blocks)
      unlist(future.apply::future_lapply(blocks, function(b) {
        out_sub <- file.path(index_dir, b)
        dir.create(out_sub, recursive = TRUE, showWarnings = FALSE)
        out_file <- file.path(out_sub, "part-0.parquet")

        # preserve_insertion_order = TRUE is required here: without it the
        # parallel writer may emit row groups out of order and the row-group
        # min/max on cited_id -- the whole basis of the fast lookup -- become
        # useless. It is deliberately FALSE in Stage 1, where order is
        # irrelevant.
        wcon <- .oas_con(memory_limit = memory_limit, temp_dir = temp_dir,
                         threads = 1L, preserve_order = TRUE)
        on.exit(DBI::dbDisconnect(wcon, shutdown = TRUE), add = TRUE)

        src <- .oas_sql_str(paste0(.oas_fwd(file.path(shards_dir, b)), "/*.parquet"))
        DBI::dbExecute(wcon, paste0(
          "COPY (SELECT DISTINCT cited_id, citing_id FROM read_parquet(", src,
          ", hive_partitioning = false) ORDER BY cited_id, citing_id) TO ",
          .oas_sql_str(.oas_fwd(out_file)),
          " (FORMAT PARQUET, COMPRESSION ", comp, ", ROW_GROUP_SIZE 200000)"
        ))
        n <- DBI::dbGetQuery(wcon, paste0(
          "SELECT count(*) AS n FROM read_parquet(",
          .oas_sql_str(.oas_fwd(out_file)), ")"))$n[[1L]]
        p()
        n
      }, future.seed = TRUE))
    },
    handlers = progressr::handler_cli()
  )

  # Metadata sidecar, written last: its presence marks the index complete.
  .oas_write_index_meta(index_dir, data.frame(
    index_type      = "citation",
    corpus_dir      = corpus_dir,
    block_size      = block_size,
    ref_encoding    = refs$enc,
    n_source_files  = length(files),
    source_bytes    = sum(file.info(files)$size, na.rm = TRUE),
    n_edges         = sum(n_edges),
    n_blocks        = length(blocks),
    built_at        = Sys.time(),
    builder_version = as.character(utils::packageVersion("openalexSnapshot")),
    stringsAsFactors = FALSE
  ))

  unlink(temp_dir, recursive = TRUE)

  if (isTRUE(verbose)) {
    sz <- sum(file.info(list.files(index_dir, recursive = TRUE,
                                   full.names = TRUE))$size, na.rm = TRUE)
    message("Done! ", format(sum(n_edges), big.mark = ","), " edges in ",
            length(blocks), " blocks, ", round(sz / 1024^3, 3), " GB (",
            round(sz / max(sum(n_edges), 1), 2), " bytes/edge)")
    message("Total time: ",
            round(difftime(Sys.time(), total_start, units = "mins"), 2),
            " minutes")
  }
  invisible(index_dir)
}
