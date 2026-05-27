# openalexSnapshot (development)

* Package created. Snapshot conversion (`snapshot_to_parquet()`), corpus
  indexing (`build_corpus_index()`), and ID-based record extraction
  (`lookup_by_id()`) have been split out of **openalexPro** into this dedicated
  package. Function signatures are preserved from the original openalexPro
  versions.
* Implementations are stubs pending the Rust back-end (openalex-core via
  extendr) and/or pure-R/DuckDB fallbacks being wired up.
