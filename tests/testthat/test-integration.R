## Integration test: oa_snapshot_to_parquet -> oa_build_corpus_index -> oa_lookup_by_id
##
## Uses real OpenAlex records extracted from /Volumes/openalex/snapshot under
## tests/testthat/fixtures/snapshot/.  The fixture mirrors the actual snapshot
## layout (data/<dataset>/updated_date=.../part_NNNN.gz) with two works
## partitions and one authors partition.
##
## Fixture coverage (works):
##   updated_date=2016-06-24/part_0000.gz  — 10 records, 8 with abstract_inverted_index, 1 no-DOI
##   updated_date=2026-03-30/part_0000.gz  — 7 records, incl. 479-author work + retracted work
##   authors/updated_date=2026-02-01/part_0000.gz — 10 records
##
## To add a "notorious case" (edge-case record that once caused a bug), extract
## the relevant .gz line from /Volumes/openalex/snapshot and append it to the
## appropriate fixture file, then add an assertion below.
##
## Example (extract line 42 from a partition):
##   python3 -c "
##     import gzip
##     with gzip.open('src.gz','rt') as f, gzip.open('fixture.gz','at') as out:
##       for i,l in enumerate(f):
##         if i == 42: out.write(l)
##   "

test_that("full snapshot pipeline works on real fixture data", {
  skip_on_cran()

  ## Guard: skip if the Rust shared library is not loaded
  if (!is.loaded("wrap__oa_snapshot_to_parquet", PACKAGE = "openalexSnapshot")) {
    skip("openalexSnapshot Rust functions not loaded")
  }

  fixture_snapshot <- testthat::test_path("fixtures", "snapshot")
  parquet_dir      <- file.path(tempdir(), paste0("oas_test_parquet_", Sys.getpid()))
  on.exit(unlink(parquet_dir, recursive = TRUE), add = TRUE)

  ## ------------------------------------------------------------------
  ## Step 1: Convert .gz fixtures to Parquet
  ## ------------------------------------------------------------------
  oa_snapshot_to_parquet(
    snapshot_dir = fixture_snapshot,
    parquet_dir  = parquet_dir,
    data_sets    = character(0),   # all datasets
    workers      = 1L,
    sample_size  = 0L,             # sample all files for schema inference
    memory_limit = "",
    temp_dir     = "",
    verbose      = FALSE
  )

  ## Both dataset directories should be created
  works_parquet   <- file.path(parquet_dir, "works")
  authors_parquet <- file.path(parquet_dir, "authors")
  expect_true(dir.exists(works_parquet),   label = "works parquet dir created")
  expect_true(dir.exists(authors_parquet), label = "authors parquet dir created")

  ## Each dataset has at least one parquet file (mirroring the partition structure)
  works_files <- list.files(works_parquet, pattern = "\\.parquet$",
                             full.names = TRUE, recursive = TRUE)
  authors_files <- list.files(authors_parquet, pattern = "\\.parquet$",
                               full.names = TRUE, recursive = TRUE)
  expect_gte(length(works_files),   2L, label = "one works parquet per source partition")
  expect_gte(length(authors_files), 1L, label = "at least one authors parquet file")

  ## ------------------------------------------------------------------
  ## Step 2: Build corpus index for works
  ## ------------------------------------------------------------------
  ## Use the returned path directly to avoid macOS /var vs /private/var discrepancy.
  index_file <- oa_build_corpus_index(
    corpus_dir   = works_parquet,
    workers      = 1L,
    memory_limit = "",
    overwrite    = FALSE,
    verbose      = FALSE
  )

  expect_true(file.exists(index_file), label = "works_id_idx.parquet created")
  expect_match(index_file, "works_id_idx\\.parquet$")

  ## Index must cover all 17 work records (10 early + 7 recent)
  idx_ds <- arrow::open_dataset(index_file) |> dplyr::collect()
  expect_equal(nrow(idx_ds), 17L, label = "index has one row per work record")
  expect_true(all(c("id", "parquet_file", "file_row_number") %in% names(idx_ds)),
              label = "index has expected columns")

  ## ------------------------------------------------------------------
  ## Step 3: Look up records — one from each source partition
  ## ------------------------------------------------------------------
  lookup_out <- file.path(tempdir(), paste0("oas_test_lookup_", Sys.getpid()))
  on.exit(unlink(lookup_out, recursive = TRUE), add = TRUE)

  target_ids <- c(
    "https://openalex.org/W146474571",   # early (2016-06-24), has abstract_inverted_index
    "https://openalex.org/W4387931303"   # recent (2026-03-30), 479-author work
  )

  oa_lookup_by_id(
    index_file = index_file,
    ids        = target_ids,
    output     = lookup_out,
    workers    = 1L,
    verbose    = FALSE
  )

  expect_true(dir.exists(lookup_out), label = "lookup output dir created")
  result_files <- list.files(lookup_out, pattern = "\\.parquet$",
                              full.names = TRUE, recursive = TRUE)
  expect_gte(length(result_files), 1L, label = "at least one result parquet file")

  result <- arrow::open_dataset(lookup_out) |> dplyr::collect()
  expect_equal(nrow(result), 2L, label = "both requested records returned")
  expect_true("id" %in% names(result), label = "id column present")
  expect_setequal(result$id, target_ids)

  ## ------------------------------------------------------------------
  ## Step 4: Notorious-case assertions
  ## ------------------------------------------------------------------

  ## Retracted work survives conversion and indexing
  retracted_id <- "https://openalex.org/W3096731654"
  expect_true(retracted_id %in% idx_ds$id,
              label = "retracted work is indexed")

  ## Large-authorship work (479 authors) round-trips correctly
  large_author_id <- "https://openalex.org/W4387931303"
  expect_true(large_author_id %in% idx_ds$id,
              label = "large-authorship work is indexed")
})
