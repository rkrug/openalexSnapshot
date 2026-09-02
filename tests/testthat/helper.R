# Mock the Rust-level entry points so the R logic can be tested without
# a compiled library.  Each mock records its call arguments in `last_call`
# so tests can assert what was passed through.

mock_oa_snapshot_to_parquet <- function(
    snapshot_dir, parquet_dir, data_sets, workers, sample_size,
    memory_limit, temp_dir, verbose) {
  last_call <<- list(
    fn           = "oa_snapshot_to_parquet",
    snapshot_dir = snapshot_dir,
    parquet_dir  = parquet_dir,
    data_sets    = data_sets,
    workers      = workers,
    sample_size  = sample_size,
    memory_limit = memory_limit,
    temp_dir     = temp_dir,
    verbose      = verbose
  )
  invisible(NULL)
}

mock_oa_build_corpus_index <- function(corpus_dir, workers, memory_limit,
                                       overwrite, verbose) {
  last_call <<- list(
    fn           = "oa_build_corpus_index",
    corpus_dir   = corpus_dir,
    workers      = workers,
    memory_limit = memory_limit,
    overwrite    = overwrite,
    verbose      = verbose
  )
  paste0(corpus_dir, "_id_idx.parquet")   # return a plausible index path
}

mock_oa_lookup_by_id <- function(index_file, ids, output, workers, verbose) {
  last_call <<- list(
    fn         = "oa_lookup_by_id",
    index_file = index_file,
    ids        = ids,
    output     = output,
    workers    = workers,
    verbose    = verbose
  )
  # Create a dummy parquet file in output so lookup_by_id() can read it back.
  if (!is.null(output) && nzchar(output)) {
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(NULL)
}


# -- parquet fixture ---------------------------------------------------------
# A tiny works corpus with the real column shapes, built in tempdir(). Used by
# every pure-R test: those must not skip on a machine without a Rust toolchain,
# which rules out the .gz fixtures that only the compiled converter can read.
#
# Deliberately includes the awkward cases: a NULL referenced_works, an empty
# '[]' one, a work with no DOI, and a SICI DOI containing < > [ ] (the regression
# anchor for the openalexPro::extract_doi() truncation bug).

make_tiny_corpus <- function(dir, n = 12L) {
  works <- file.path(dir, "parquet", "works", "updated_date=2020-01-01")
  dir.create(works, recursive = TRUE, showWarnings = FALSE)

  # IDs are spread 4e6 apart so that at the default block_size of 1e7 the
  # cited works span several cited_block partitions, exercising pruning
  # instead of everything landing in block 0.
  num <- 1000000L + (seq_len(n) - 1L) * 4000000L
  short <- paste0("W", format(num, scientific = FALSE, trim = TRUE))
  ids <- paste0("https://openalex.org/", short)

  dois <- paste0("https://doi.org/10.1234/test.", seq_len(n))
  # Real SICI DOIs: the regression anchor for the extract_doi() truncation bug.
  dois[3L] <- "https://doi.org/10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2"
  dois[4L] <- "https://doi.org/10.1577/1548-8659(1973)35[142:amosss]2.0.co;2"
  dois[n]  <- NA_character_                       # a work with no DOI

  # Explicit edge set, so tests can reason about exact counts.
  #   * work 1 has NULL references
  #   * work 2 has "[]"
  #   * works 3+ cite a spread of earlier works, chosen to land in different
  #     cited_blocks (indices 1, 4, 7, 10 sit in blocks 0, 1, 2, 3)
  #   * works 5 and 6 also cite a dangling id absent from the corpus, so the
  #     "outside" edge class is non-empty downstream
  spread <- c(1L, 4L, 7L, 10L)
  refs <- vapply(seq_len(n), function(i) {
    if (i == 1L) return(NA_character_)
    if (i == 2L) return("[]")
    targets <- ids[spread[spread < i]]
    if (length(targets) == 0L) targets <- ids[1L]
    if (i %in% c(5L, 6L)) {
      targets <- c(targets, "https://openalex.org/W999000111")   # dangling
    }
    paste0("[", paste0('"', targets, '"', collapse = ","), "]")
  }, character(1))

  df <- data.frame(
    id = ids,
    doi = dois,
    title = paste("Work", seq_len(n)),
    publication_year = 2000L + seq_len(n),
    referenced_works = refs,
    stringsAsFactors = FALSE
  )
  df$referenced_works_count <- vapply(refs, function(x) {
    if (is.na(x) || x == "[]") 0L
    else length(gregexpr("openalex\\.org/W", x)[[1L]])
  }, integer(1))

  arrow::write_parquet(df, file.path(works, "part_0000.parquet"))
  file.path(dir, "parquet", "works")
}

# Short ids of the fixture works, in order. Tests use these rather than
# hard-coding, so the id scheme can change in one place.
tiny_ids <- function(n = 12L) {
  paste0("W", format(1000000L + (seq_len(n) - 1L) * 4000000L,
                     scientific = FALSE, trim = TRUE))
}
