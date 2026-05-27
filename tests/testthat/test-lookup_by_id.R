test_that("lookup_by_id() errors when ids is missing", {
  expect_error(
    lookup_by_id(root_dir = "/vol"),
    "ids.*must be provided"
  )
})

test_that("lookup_by_id() errors when ids is empty", {
  expect_error(
    lookup_by_id(root_dir = "/vol", ids = character(0)),
    "ids.*must be provided"
  )
})

test_that("lookup_by_id() errors when neither root_dir nor index_file given", {
  expect_error(
    lookup_by_id(ids = "W123"),
    "Provide either `root_dir` or `index_file`"
  )
})

test_that("lookup_by_id() index_file mode calls oa_lookup_by_id with output dir", {
  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE))

  last_call <<- NULL
  lookup_by_id(index_file = "works.parquet", ids = "W123", output = tmp)

  expect_equal(last_call$fn,         "oa_lookup_by_id")
  expect_equal(last_call$index_file, "works.parquet")
  expect_equal(last_call$ids,        "W123")
  expect_equal(last_call$output,     tmp)
})

test_that("lookup_by_id() index_file + output mode returns output path invisibly", {
  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE))

  result <- lookup_by_id(index_file = "works.parquet", ids = "W123", output = tmp)
  expect_equal(result, tmp)
})

test_that("lookup_by_id() index_file mode with NULL output returns empty data.frame when no hits", {
  local_mocked_bindings(
    oa_lookup_by_id = function(index_file, ids, output, workers, verbose) {
      # Don't create any files — simulates zero matches.
      dir.create(output, recursive = TRUE, showWarnings = FALSE)
      invisible(NULL)
    },
    .env = asNamespace("openalexSnapshot")
  )
  result <- NULL
  expect_message(
    {result <- lookup_by_id(index_file = "works.parquet", ids = "W999")},
    "No matching records found"
  )
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})

test_that("lookup_by_id() coerces ids to character", {
  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE))

  last_call <<- NULL
  # Pass numeric-looking strings — should still reach Rust as character
  lookup_by_id(index_file = "idx.parquet", ids = c("W1", "W2"), output = tmp)
  expect_type(last_call$ids, "character")
  expect_equal(last_call$ids, c("W1", "W2"))
})

test_that("lookup_by_id() converts workers to integer", {
  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE))

  last_call <<- NULL
  lookup_by_id(index_file = "idx.parquet", ids = "W1", output = tmp, workers = 3)
  expect_identical(last_call$workers, 3L)
})

test_that("lookup_by_id() defaults workers to 1L", {
  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE))

  last_call <<- NULL
  lookup_by_id(index_file = "idx.parquet", ids = "W1", output = tmp)
  expect_identical(last_call$workers, 1L)
})

test_that("lookup_by_id() root_dir mode errors when no index files found", {
  tmp_root <- tempfile()
  dir.create(file.path(tmp_root, "parquet"), recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE))

  expect_error(
    lookup_by_id(root_dir = tmp_root, ids = "W123", project_dir = tempfile()),
    "No index files found"
  )
})

test_that("lookup_by_id() root_dir mode errors when project_dir not given", {
  tmp_root <- tempfile()
  parq_dir <- file.path(tmp_root, "parquet")
  dir.create(parq_dir, recursive = TRUE)
  # Create a fake index file so dataset discovery succeeds
  file.create(file.path(parq_dir, "works_id_idx.parquet"))
  on.exit(unlink(tmp_root, recursive = TRUE))

  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )

  expect_error(
    lookup_by_id(root_dir = tmp_root, ids = "W123"),
    "project_dir must be provided"
  )
})

test_that("lookup_by_id() root_dir mode skips missing index files with message", {
  tmp_root <- tempfile()
  parq_dir <- file.path(tmp_root, "parquet")
  dir.create(parq_dir, recursive = TRUE)
  on.exit(unlink(tmp_root, recursive = TRUE))

  local_mocked_bindings(
    oa_lookup_by_id = mock_oa_lookup_by_id,
    .env = asNamespace("openalexSnapshot")
  )

  expect_message(
    lookup_by_id(
      root_dir    = tmp_root,
      ids         = "W123",
      data_sets   = "works",
      project_dir = tempfile()
    ),
    "No index for dataset 'works'"
  )
})

test_that("lookup_by_id() root_dir mode calls oa_lookup_by_id for each dataset", {
  tmp_root <- tempfile()
  parq_dir <- file.path(tmp_root, "parquet")
  dir.create(parq_dir, recursive = TRUE)
  # Create fake index files for two datasets
  file.create(file.path(parq_dir, "works_id_idx.parquet"))
  file.create(file.path(parq_dir, "authors_id_idx.parquet"))
  on.exit(unlink(tmp_root, recursive = TRUE))

  calls <- list()
  local_mocked_bindings(
    oa_lookup_by_id = function(index_file, ids, output, workers, verbose) {
      calls[[length(calls) + 1L]] <<- index_file
      dir.create(output, recursive = TRUE, showWarnings = FALSE)
      invisible(NULL)
    },
    .env = asNamespace("openalexSnapshot")
  )

  proj <- tempfile()
  lookup_by_id(
    root_dir    = tmp_root,
    ids         = "W123",
    data_sets   = c("works", "authors"),
    project_dir = proj
  )

  expect_length(calls, 2L)
  expect_match(calls[[1L]], "works_id_idx\\.parquet$")
  expect_match(calls[[2L]], "authors_id_idx\\.parquet$")
})

test_that("lookup_by_id() root_dir mode returns project_dir invisibly", {
  tmp_root <- tempfile()
  parq_dir <- file.path(tmp_root, "parquet")
  dir.create(parq_dir, recursive = TRUE)
  file.create(file.path(parq_dir, "works_id_idx.parquet"))
  on.exit(unlink(tmp_root, recursive = TRUE))

  proj <- tempfile()
  local_mocked_bindings(
    oa_lookup_by_id = function(index_file, ids, output, workers, verbose) {
      dir.create(output, recursive = TRUE, showWarnings = FALSE)
      invisible(NULL)
    },
    .env = asNamespace("openalexSnapshot")
  )

  result <- lookup_by_id(
    root_dir    = tmp_root,
    ids         = "W123",
    data_sets   = "works",
    project_dir = proj
  )
  expect_equal(result, proj)
})
