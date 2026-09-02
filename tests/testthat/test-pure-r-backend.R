# Tests for the pure-R/DuckDB backend.
#
# These need a real parquet corpus, so they build a tiny one in tempdir()
# rather than mocking. That is deliberate: the whole point of the pure-R
# backend is that it can be exercised without a compiled library, so these
# tests must not skip on a machine that has no Rust toolchain.

make_tiny_corpus <- function(dir, n = 12L, start = 1000000L) {
  works <- file.path(dir, "parquet", "works", "updated_date=2020-01-01")
  dir.create(works, recursive = TRUE, showWarnings = FALSE)
  ids <- paste0("https://openalex.org/W", start + seq_len(n))
  df <- data.frame(
    id = ids,
    doi = c(paste0("https://doi.org/10.1234/test.", seq_len(n - 1L)), NA),
    title = paste("Work", seq_len(n)),
    publication_year = 2000L + seq_len(n),
    stringsAsFactors = FALSE
  )
  # referenced_works as a JSON VARCHAR, matching the legacy converted corpus
  df$referenced_works <- vapply(seq_len(n), function(i) {
    if (i == 1L) return(NA_character_)
    if (i == 2L) return("[]")
    paste0("[", paste0('"', ids[seq_len(min(i - 1L, 3L))], '"', collapse = ","), "]")
  }, character(1))
  arrow::write_parquet(df, file.path(works, "part_0000.parquet"))
  file.path(dir, "parquet", "works")
}

test_that(".oas_parquet_root accepts a root_dir, a parquet dir, or neither", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  expect_equal(.oas_parquet_root(tmp), normalizePath(file.path(tmp, "parquet")))
  expect_equal(.oas_parquet_root(file.path(tmp, "parquet")),
               normalizePath(file.path(tmp, "parquet")))
  # non-existent paths derive without erroring (path derivation != validation)
  expect_equal(.oas_parquet_root("/vol"), file.path("/vol", "parquet"))
  expect_error(.oas_parquet_root("/vol", must_exist = TRUE), "does not exist")
})

test_that("build_corpus_index(backend = 'r') produces the documented schema", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)

  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)
  expect_true(file.exists(idx))
  expect_match(idx, "works_id_idx\\.parquet$")

  got <- as.data.frame(arrow::read_parquet(idx))
  expect_equal(sort(names(got)),
               c("file_row_number", "id", "id_block", "parquet_file"))
  expect_equal(nrow(got), 12L)

  # id is long form; parquet_file is relative to the parquet root and includes
  # the dataset name; file_row_number is 0-indexed
  expect_true(all(grepl("^https://openalex\\.org/W", got$id)))
  expect_equal(unique(got$parquet_file),
               "works/updated_date=2020-01-01/part_0000.parquet")
  expect_equal(sort(got$file_row_number), 0:11)

  # id_block matches the documented floor(numeric_id / 10000)
  expect_equal(got$id_block, .oas_id_block(got$id))
})

test_that("build_corpus_index(backend = 'r') respects overwrite", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)
  before <- file.info(idx)$mtime

  expect_message(
    build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE),
    "creation skipped"
  )
  expect_equal(file.info(idx)$mtime, before)

  build_corpus_index(corpus_dir = corpus, backend = "r", overwrite = TRUE,
                     verbose = FALSE)
  expect_true(file.exists(idx))
})

test_that("lookup_by_id(backend = 'r') round-trips records", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)
  ids <- paste0("W", 1000001L:1000003L)

  got <- lookup_by_id(ids = ids, index_file = idx, backend = "r", verbose = FALSE)
  expect_equal(nrow(got), 3L)
  expect_setequal(got$id, .oas_normalize_id(ids))
  # file_row_number is an index artefact and must not leak into the result
  expect_false("file_row_number" %in% names(got))
})

test_that("lookup_by_id(backend = 'r') accepts short and long form ids alike", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)

  short <- lookup_by_id(ids = "W1000001", index_file = idx, backend = "r",
                        verbose = FALSE)
  long  <- lookup_by_id(ids = "https://openalex.org/W1000001", index_file = idx,
                        backend = "r", verbose = FALSE)
  expect_equal(short$id, long$id)
})

test_that("lookup_by_id(backend = 'r') projects columns", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)

  got <- lookup_by_id(ids = "W1000005", index_file = idx, backend = "r",
                      columns = c("id", "referenced_works"), verbose = FALSE)
  expect_equal(names(got), c("id", "referenced_works"))
})

test_that("lookup_by_id(backend = 'r') injects add_columns as SQL literals", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)

  got <- lookup_by_id(
    ids = c("W1000001", "W1000002"), index_file = idx, backend = "r",
    columns = "id",
    add_columns = list(oa_input = "TRUE", relation = "keypaper"),
    verbose = FALSE
  )
  expect_equal(names(got), c("id", "oa_input", "relation"))
  # Values arrive as VARCHAR, matching openalexPro::pro_request_parquet(); the
  # cast to BOOLEAN happens at node assembly. This is a contract, not an
  # accident - openalexSnowball shares one assembly step across both paths.
  expect_type(got$oa_input, "character")
  expect_equal(unique(got$oa_input), "TRUE")
  expect_equal(unique(got$relation), "keypaper")
})

test_that("lookup_by_id(backend = 'r') writes parquet when output is given", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)
  out <- file.path(tmp, "extract")

  res <- lookup_by_id(ids = c("W1000001", "W1000002"), index_file = idx,
                      backend = "r", output = out, verbose = FALSE)
  expect_equal(res, out)
  expect_gt(length(list.files(out, pattern = "\\.parquet$")), 0L)
  expect_equal(nrow(dplyr::collect(arrow::open_dataset(out))), 2L)
})

test_that("lookup_by_id(backend = 'r') reports no matches without erroring", {
  tmp <- withr::local_tempdir()
  corpus <- make_tiny_corpus(tmp)
  idx <- build_corpus_index(corpus_dir = corpus, backend = "r", verbose = FALSE)

  expect_message(
    got <- lookup_by_id(ids = "W999999999", index_file = idx, backend = "r",
                        verbose = TRUE),
    "No matching records"
  )
  expect_equal(nrow(got), 0L)

  # verbose = FALSE really is silent
  expect_silent(
    lookup_by_id(ids = "W999999999", index_file = idx, backend = "r",
                 verbose = FALSE)
  )
})

test_that("a missing index raises a typed condition naming its builder", {
  tmp <- withr::local_tempdir()
  expect_error(
    lookup_by_id(ids = "W1", index_file = file.path(tmp, "absent_id_idx.parquet"),
                 backend = "r", verbose = FALSE),
    class = "openalexSnapshot_missing_id_index"
  )
  expect_error(
    lookup_by_id(ids = "W1", index_file = file.path(tmp, "absent_id_idx.parquet"),
                 backend = "r", verbose = FALSE),
    class = "openalexSnapshot_missing_index"
  )
})

test_that("columns and add_columns are refused on the rust backend", {
  skip_if_not(.oas_rust_available(), "compiled library not loaded")
  expect_error(
    lookup_by_id(ids = "W1", index_file = "x", backend = "rust",
                 columns = "id"),
    'require backend = "r"'
  )
})

test_that("backend = 'auto' resolves to rust when loaded, r otherwise", {
  expect_equal(.oas_backend("auto"),
               if (.oas_rust_available()) "rust" else "r")
  expect_equal(.oas_backend("r"), "r")
})
