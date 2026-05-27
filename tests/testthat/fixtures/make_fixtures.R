## make_fixtures.R
##
## Generates small but realistic OpenAlex .json.gz fixture files for
## integration tests.  Run this script once and commit the resulting
## .json.gz files; the script is kept for documentation.
##
## Usage (from the package root):
##   Rscript tests/testthat/fixtures/make_fixtures.R

library(jsonlite)

fixture_root <- file.path(
  "tests", "testthat", "fixtures", "snapshot", "data"
)

works_dir   <- file.path(fixture_root, "works",   "updated_date=2024-01-01")
authors_dir <- file.path(fixture_root, "authors", "updated_date=2024-01-01")

dir.create(works_dir,   recursive = TRUE, showWarnings = FALSE)
dir.create(authors_dir, recursive = TRUE, showWarnings = FALSE)

## ---- helpers ----------------------------------------------------------------

write_gz <- function(records, path) {
  lines <- vapply(records, function(r) toJSON(r, auto_unbox = TRUE), character(1))
  con   <- gzfile(path, open = "wb")
  writeBin(chartr("\n", " ", paste(lines, collapse = "\n")), con)
  ## write each line separately so the file is valid NDJSON
  close(con)
  con <- gzfile(path, open = "wt")
  writeLines(lines, con)
  close(con)
  invisible(path)
}

## ---- work record factory ----------------------------------------------------

make_work <- function(n) {
  base_id <- 2741809807 + n - 1
  id_url  <- paste0("https://openalex.org/W", base_id)
  list(
    id           = id_url,
    doi          = paste0("https://doi.org/10.1000/test.", n),
    title        = paste("Test Work Title Number", n),
    display_name = paste("Test Work Title Number", n),
    publication_year = 2020L + (n %% 4L),
    publication_date = paste0(2020L + (n %% 4L), "-01-", sprintf("%02d", n)),
    type         = "article",
    cited_by_count = as.integer(n * 3),
    is_retracted = FALSE,
    is_paratext  = FALSE,
    updated_date = "2024-01-01",
    created_date = "2016-06-24",
    authorships  = list(list(
      author_position    = "first",
      author             = list(
        id           = paste0("https://openalex.org/A", 1234567890L + n - 1L),
        display_name = paste("Author", n),
        orcid        = NULL
      ),
      institutions        = list(),
      is_corresponding    = TRUE,
      raw_author_name     = paste("Author", n),
      raw_affiliation_strings = list()
    )),
    biblio = list(
      volume     = as.character(100L + n),
      issue      = as.character(n %% 12L + 1L),
      first_page = as.character(n),
      last_page  = as.character(n + 9L)
    ),
    primary_location = list(
      source = list(
        id           = "https://openalex.org/S137773608",
        display_name = "Test Journal",
        type         = "journal"
      ),
      landing_page_url = NULL,
      pdf_url          = NULL,
      is_oa            = FALSE,
      oa_status        = "closed"
    ),
    open_access = list(
      is_oa                    = FALSE,
      oa_status                = "closed",
      oa_url                   = NULL,
      any_repository_has_fulltext = FALSE
    ),
    best_oa_location = NULL,
    locations        = list(),
    referenced_works = list(),
    related_works    = list(),
    concepts         = list(),
    mesh             = list(),
    keywords         = list(),
    abstract_inverted_index = NULL,
    counts_by_year   = list(),
    sustainable_development_goals = list(),
    grants           = list(),
    datasets         = list(),
    versions         = list(),
    language         = "en",
    ids              = list(
      openalex = id_url,
      doi      = paste0("https://doi.org/10.1000/test.", n)
    )
  )
}

## ---- author record factory --------------------------------------------------

make_author <- function(n) {
  id_url <- paste0("https://openalex.org/A", 1234567890L + n - 1L)
  list(
    id           = id_url,
    orcid        = NULL,
    display_name = paste("Author", n),
    display_name_alternatives = list(),
    works_count  = as.integer(n * 10),
    cited_by_count = as.integer(n * 25),
    summary_stats = list(
      `2yr_mean_citedness` = round(n * 0.5, 2),
      h_index   = as.integer(n + 5),
      i10_index = as.integer(n + 2)
    ),
    ids = list(
      openalex = id_url,
      orcid    = NULL
    ),
    affiliations          = list(),
    last_known_institutions = list(),
    topics                = list(),
    x_concepts            = list(),
    counts_by_year        = list(),
    works_api_url = paste0(
      "https://api.openalex.org/works?filter=author.id:A",
      1234567890L + n - 1L
    ),
    updated_date = "2024-01-01",
    created_date = "2016-06-24"
  )
}

## ---- write works (2 files, 5 records each) ----------------------------------

write_gz(lapply(1:5,  make_work), file.path(works_dir, "part_000.json.gz"))
write_gz(lapply(6:10, make_work), file.path(works_dir, "part_001.json.gz"))

## ---- write authors (1 file, 3 records) --------------------------------------

write_gz(lapply(1:3, make_author), file.path(authors_dir, "part_000.json.gz"))

message("Fixtures written to ", fixture_root)
