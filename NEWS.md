# openalexSnapshot 0.1.0

## Design change: pure R by default, Rust as an optional accelerator

* **The "Rust-only, no pure-R fallback" decision recorded in 0.0.0.9000 is
  retracted.** Part 4 of the ecosystem `compatibility_report.md` measured the
  actual benefit: for `index` and `extract` the work is parquet decode and
  write rather than computation, a single DuckDB thread already saturates the
  pipeline, and the corpus lives on an external volume where cold I/O dominates
  and is language-neutral. The expected Rust advantage is ~1.0-1.5x. `enrich`
  was the one genuine win (~10x), and moving enrichment from download-time to
  extract-time removes that step in batch form entirely.

* `build_corpus_index()` and `lookup_by_id()` gain
  `backend = c("auto", "r", "rust")`. `"auto"` (the default) uses the compiled
  library when it is loaded and pure R otherwise, so **existing behaviour is
  unchanged**. `"r"` is always available and is what CI exercises.

* `lookup_by_id()` gains `columns =` (column projection) and `add_columns =`
  (inject constant columns). Both were impossible on the Rust path, which does
  `SELECT *`; projection matters when reading 2 of 51 columns from a corpus of
  nested structs.

* `snapshot_to_parquet()` remains **Rust-only**. It is the hardest to port, it
  is not on the critical path, and the official OpenAlex snapshot is now
  published natively in parquet, making JSON conversion a legacy path.

* `DESCRIPTION` previously claimed "a pure-R/DuckDB fallback is included for
  environments without a Rust toolchain", which was not true of the shipped
  code. It is now accurate. `SystemRequirements` records that Rust is needed
  only for `snapshot_to_parquet()`.

* Added the missing `VignetteBuilder: quarto` — the two `.qmd` vignettes could
  not previously be built.

# openalexSnapshot 0.0.0.9000

* Package created. Snapshot conversion (`snapshot_to_parquet()`), corpus
  indexing (`build_corpus_index()`), and ID-based record extraction
  (`lookup_by_id()`) have been split out of **openalexPro** into this dedicated
  package. Function signatures are preserved from the original openalexPro
  versions.
* **Rust-only design**: no pure-R fallback is planned. Installation friction is
  addressed by pre-compiled r-universe binaries rather than a second
  implementation. Only package developers need a Rust toolchain.
  **Retracted in 0.1.0** — see below.
* Rust back-end (`openalex-core` via extendr) wired up; all three functions
  delegate to compiled Rust code.
