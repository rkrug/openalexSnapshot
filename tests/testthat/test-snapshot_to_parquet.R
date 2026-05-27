test_that("snapshot_to_parquet() errors when no path arguments given", {
  expect_error(
    snapshot_to_parquet(),
    "Provide either `root_dir` or both `snapshot_dir` and `parquet_dir`"
  )
})

test_that("snapshot_to_parquet() errors when only snapshot_dir is given", {
  expect_error(
    snapshot_to_parquet(snapshot_dir = "/tmp/snap"),
    "Provide either `root_dir` or both `snapshot_dir` and `parquet_dir`"
  )
})

test_that("snapshot_to_parquet() errors when only parquet_dir is given", {
  expect_error(
    snapshot_to_parquet(parquet_dir = "/tmp/parq"),
    "Provide either `root_dir` or both `snapshot_dir` and `parquet_dir`"
  )
})

test_that("snapshot_to_parquet() resolves paths from root_dir", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/Volumes/openalex")

  expect_equal(last_call$snapshot_dir, "/Volumes/openalex/openalex-snapshot")
  expect_equal(last_call$parquet_dir,  "/Volumes/openalex/parquet")
})

test_that("snapshot_to_parquet() passes explicit paths through unchanged", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(snapshot_dir = "/data/snap", parquet_dir = "/data/parq")

  expect_equal(last_call$snapshot_dir, "/data/snap")
  expect_equal(last_call$parquet_dir,  "/data/parq")
})

test_that("snapshot_to_parquet() passes data_sets as character vector", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", data_sets = c("works", "authors"))

  expect_equal(last_call$data_sets, c("works", "authors"))
})

test_that("snapshot_to_parquet() passes empty character(0) when data_sets is NULL", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", data_sets = NULL)

  expect_equal(last_call$data_sets, character(0L))
})

test_that("snapshot_to_parquet() converts workers to integer", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", workers = 4)

  expect_identical(last_call$workers, 4L)
})

test_that("snapshot_to_parquet() defaults workers to 1L (sequential)", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x")

  expect_identical(last_call$workers, 1L)
})

test_that("snapshot_to_parquet() converts sample_size=0 / NULL to 0L", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", sample_size = 0)
  expect_identical(last_call$sample_size, 0L)

  snapshot_to_parquet(root_dir = "/x", sample_size = NULL)
  expect_identical(last_call$sample_size, 0L)
})

test_that("snapshot_to_parquet() passes memory_limit as string", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", memory_limit = "8GB")
  expect_equal(last_call$memory_limit, "8GB")

  snapshot_to_parquet(root_dir = "/x", memory_limit = NULL)
  expect_equal(last_call$memory_limit, "")
})

test_that("snapshot_to_parquet() passes temp_directory as string", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  last_call <<- NULL
  snapshot_to_parquet(root_dir = "/x", temp_directory = "/tmp/duckdb")
  expect_equal(last_call$temp_dir, "/tmp/duckdb")

  snapshot_to_parquet(root_dir = "/x", temp_directory = NULL)
  expect_equal(last_call$temp_dir, "")
})

test_that("snapshot_to_parquet() returns NULL invisibly", {
  local_mocked_bindings(
    oa_snapshot_to_parquet = mock_oa_snapshot_to_parquet,
    .package = "openalexSnapshot"
  )
  result <- snapshot_to_parquet(root_dir = "/x")
  expect_null(result)
})
