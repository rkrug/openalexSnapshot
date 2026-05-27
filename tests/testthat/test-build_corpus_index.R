test_that("build_corpus_index() errors when no path arguments given", {
  expect_error(
    build_corpus_index(),
    "Provide either `root_dir` or `corpus_dir`"
  )
})

test_that("build_corpus_index() uses corpus_dir mode when corpus_dir is provided", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  last_call <<- NULL
  build_corpus_index(corpus_dir = "/data/parquet/works")

  expect_equal(last_call$fn,         "oa_build_corpus_index")
  expect_equal(last_call$corpus_dir, "/data/parquet/works")
})

test_that("build_corpus_index() corpus_dir mode returns invisible index path", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  result <- build_corpus_index(corpus_dir = "/data/parquet/works")
  # Result is invisible; accessing it gives the index path
  expect_match(result, "works_id_idx\\.parquet$")
})

test_that("build_corpus_index() passes workers as integer", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  last_call <<- NULL
  build_corpus_index(corpus_dir = "/data/works", workers = 4)
  expect_identical(last_call$workers, 4L)
})

test_that("build_corpus_index() defaults workers to 1L", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  last_call <<- NULL
  build_corpus_index(corpus_dir = "/data/works")
  expect_identical(last_call$workers, 1L)
})

test_that("build_corpus_index() passes memory_limit as string", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  last_call <<- NULL
  build_corpus_index(corpus_dir = "/data/works", memory_limit = "20GB")
  expect_equal(last_call$memory_limit, "20GB")

  build_corpus_index(corpus_dir = "/data/works", memory_limit = NULL)
  expect_equal(last_call$memory_limit, "")
})

test_that("build_corpus_index() passes overwrite flag correctly", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  last_call <<- NULL
  build_corpus_index(corpus_dir = "/data/works", overwrite = TRUE)
  expect_true(last_call$overwrite)

  build_corpus_index(corpus_dir = "/data/works", overwrite = FALSE)
  expect_false(last_call$overwrite)
})

test_that("build_corpus_index() root_dir mode iterates over provided data_sets", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  calls <- list()
  with_mocked_bindings(
    oa_build_corpus_index = function(corpus_dir, ...) {
      calls[[length(calls) + 1L]] <<- corpus_dir
      paste0(corpus_dir, "_id_idx.parquet")
    },
    {
      build_corpus_index(root_dir = "/vol", data_sets = c("works", "authors"))
    },
    .env = asNamespace("openalexSnapshot")
  )
  expect_length(calls, 2L)
  expect_equal(calls[[1L]], "/vol/parquet/works")
  expect_equal(calls[[2L]], "/vol/parquet/authors")
})

test_that("build_corpus_index() root_dir mode returns root_dir invisibly", {
  local_mocked_bindings(
    oa_build_corpus_index = mock_oa_build_corpus_index,
    .env = asNamespace("openalexSnapshot")
  )
  result <- build_corpus_index(root_dir = "/vol", data_sets = "works")
  expect_equal(result, "/vol")
})
