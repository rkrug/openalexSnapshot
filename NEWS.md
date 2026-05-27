# openalexSnapshot (development)

* Package created. Snapshot conversion (`snapshot_to_parquet()`), corpus
  indexing (`build_corpus_index()`), and ID-based record extraction
  (`lookup_by_id()`) have been split out of **openalexPro** into this dedicated
  package. Function signatures are preserved from the original openalexPro
  versions.
* **Rust-only design**: no pure-R fallback is planned. Installation friction is
  addressed by pre-compiled r-universe binaries rather than a second
  implementation. Only package developers need a Rust toolchain.
* Current implementations are stubs pending the Rust back-end (openalex-core
  via extendr) being wired up.
