## Integration test: snapshot_to_parquet -> build_corpus_index -> lookup_by_id
##
## Uses small fixture files under tests/testthat/fixtures/snapshot/.
## Skipped on CRAN and when the package is not compiled.

test_that("full snapshot pipeline works on fixture data", {
  skip_on_cran()

  ## Guard: skip if the Rust shared library is not compiled in
  if (!nzchar(system.file(package = "openalexSnapshot", "libs", mustWork = FALSE))) {
    skip("openalexSnapshot not compiled")
  }

  fixture_snapshot <- testthat::test_path("fixtures", "snapshot")
  parquet_dir      <- file.path(tempdir(), paste0("oas_test_parquet_", Sys.getpid()))
  on.exit(unlink(parquet_dir, recursive = TRUE), add = TRUE)

  ## ------------------------------------------------------------------
  ## Step 1: Convert JSON.GZ fixtures to Parquet
  ## ------------------------------------------------------------------
  oa_snapshot_to_parquet(
    snapshot_dir = fixture_snapshot,
    parquet_dir  = parquet_dir,
    data_sets    = character(0),   # all datasets
    workers      = 1L,
    sample_size  = 0L,
    memory_limit = "",
    temp_dir     = "",
    verbose      = FALSE
  )

  ## Works parquet files
  works_parquet <- file.path(parquet_dir, "works")
  expect_true(dir.exists(works_parquet), label = "works parquet dir created")
  works_files <- list.files(works_parquet, pattern = "\\.parquet$", full.names = TRUE)
  expect_gte(length(works_files), 1L, label = "at least one works parquet file")

  ## Authors parquet files
  authors_parquet <- file.path(parquet_dir, "authors")
  expect_true(dir.exists(authors_parquet), label = "authors parquet dir created")
  authors_files <- list.files(authors_parquet, pattern = "\\.parquet$", full.names = TRUE)
  expect_gte(length(authors_files), 1L, label = "at least one authors parquet file")

  ## ------------------------------------------------------------------
  ## Step 2: Build corpus index for works
  ## ------------------------------------------------------------------
  oa_build_corpus_index(
    corpus_dir   = works_parquet,
    workers      = 1L,
    memory_limit = "",
    overwrite    = FALSE,
    verbose      = FALSE
  )

  index_file <- file.path(parquet_dir, "works_id_idx.parquet")
  expect_true(file.exists(index_file), label = "works_id_idx.parquet created")

  ## ------------------------------------------------------------------
  ## Step 3: Look up two work IDs
  ## ------------------------------------------------------------------
  lookup_out <- file.path(tempdir(), paste0("oas_test_lookup_", Sys.getpid()))
  on.exit(unlink(lookup_out, recursive = TRUE), add = TRUE)

  target_ids <- c(
    "https://openalex.org/W2741809807",
    "https://openalex.org/W2741809812"
  )

  oa_lookup_by_id(
    index_file = index_file,
    ids        = target_ids,
    output     = lookup_out,
    workers    = 1L,
    verbose    = FALSE
  )

  ## ------------------------------------------------------------------
  ## Step 4: Read results and verify
  ## ------------------------------------------------------------------
  expect_true(dir.exists(lookup_out), label = "lookup output dir created")

  result_files <- list.files(lookup_out, pattern = "\\.parquet$",
                              full.names = TRUE, recursive = TRUE)
  expect_gte(length(result_files), 1L, label = "at least one result parquet file")

  result <- arrow::open_dataset(lookup_out) |> dplyr::collect()

  expect_gte(nrow(result), 1L, label = "at least one row returned")
  expect_true("id" %in% names(result), label = "id column present")

  returned_ids <- result$id
  expect_true(
    any(returned_ids %in% target_ids),
    label = "at least one of the requested IDs is in the result"
  )
})
