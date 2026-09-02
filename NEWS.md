# openalexSnapshot 0.1.0

## New: offline citation graph

The snapshot can now answer "which works cite this one?" without network
access. `cited_by_api_url` is a URL and useless offline, but the citing
direction is recoverable by inverting the `referenced_works` every work
already carries.

* **`build_citation_index()`** inverts `referenced_works` into an edge set
  keyed by the cited work. Unlike the `_id_idx` and `_doi_idx` files this is a
  hive-partitioned **directory** (`works_cite_idx/cited_block=N/`), because the
  full corpus holds roughly three billion edges: a single sorted file would
  need a global sort of that many rows and a footer costing tens of MB to parse
  per query. Measured on the real corpus this costs about 5 bytes per edge
  (~15 GB total) and turns a 20-second scan into a 5-millisecond lookup.

* **`build_doi_index()`** builds `works_doi_idx.parquet`, so DOIs resolve
  offline. DOIs are accepted with or without a resolver prefix -- bare,
  `https://doi.org/`, `http://dx.doi.org/`, `doi:` and mixed case all normalise
  to the same key.

* **`get_citing()`** and **`get_cited()`** query the above. `keypaper` is a
  vector and may mix short IDs, long IDs, bare DOIs and resolver DOIs in one
  call; all are resolved and queried in a single pass. The default return is an
  edge list (`from`, `to`, where a row `A, B` means A cites B) rather than a
  flat ID vector, which keeps the mapping between each keypaper and its
  neighbours. `return = "ids"` and `return = "records"` are also available.

  `get_cited()` deliberately needs **no** citation index: the works a paper
  references are simply its own `referenced_works`.

* **`doi_to_id()`** and **`lookup_by_doi()`** resolve and extract by DOI.
  Unresolved DOIs are returned as `NA` in input order and warned about, never
  silently dropped.

* Missing indexes raise typed conditions
  (`openalexSnapshot_missing_citation_index` and friends) naming the builder
  that creates them, and distinguish an absent index from an interrupted build.
  An index that looks out of step with the corpus **warns rather than errors** --
  a deliberately frozen snapshot must stay usable.

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
