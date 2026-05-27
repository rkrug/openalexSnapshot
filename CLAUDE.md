# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Package Does

**openalexSnapshot** is an R package for working with the [OpenAlex](https://openalex.org) bulk
snapshot. It handles the large-scale, offline data pipeline:

1. **`snapshot_to_parquet()`** — converts `.json.gz` snapshot files to Parquet (schema inference
   + parallel conversion)
2. **`build_corpus_index()`** — builds `<dataset>_id_idx.parquet` ID-lookup indexes over the
   Parquet corpus
3. **`lookup_by_id()`** — extracts records by OpenAlex ID using the index

These functions were split out of **openalexPro** (v0.10.0). Calling them in `openalexPro` raises
an informative error pointing users here.

## Architecture

### Current state (stubs)

All three functions currently raise "not yet implemented" errors. They have the correct argument
signatures (preserved from openalexPro). The actual implementations need to be wired up:

- **Rust back-end**: `openalex-core` (at `~/GitHub/openalex-snapshot`) provides a Rust library
  that can be exposed to R via [extendr](https://extendr.github.io/). This is the preferred path
  for performance-critical bulk conversion.
- **Pure-R/DuckDB fallback**: The `_R` variants from openalexPro can serve as a starting point.
  They were removed from openalexPro as part of the split but are recoverable from git history
  (`git show 70539a0:R/snapshot_to_parquet.R` etc. in the openalexPro repo).

### Rust back-end (openalex-core)

`~/GitHub/openalex-snapshot/src/main.rs` contains the Rust implementation of the snapshot
conversion pipeline. The key functions are:
- `snapshot_to_parquet` — JSON.GZ → Parquet per dataset
- `build_corpus_index` — two-stage indexing (per-file shards → combined index)
- `lookup_by_id` — ID routing via entity prefix (`W`=works, `A`=authors, etc.)

To expose these via extendr, add a `src/rust/` directory with a library crate that wraps
`openalex-core` and uses `#[extendr]` attributes.

## Common Commands

```r
devtools::load_all()      # Load package
devtools::document()      # Regenerate roxygen2 docs and NAMESPACE
devtools::test()          # Run all tests
devtools::check()         # Full R CMD CHECK
```

## Branching

- Work on `claude/<description>` branches from `main` (single-branch repo for now)
- `main` receives release commits

## Key Conventions

- `root_dir` is the standard top-level directory parameter (consistent with openalexPro's
  `project_dir` convention for API work)
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form
  (`https://openalex.org/W2741809807`)
- Index files are named `<dataset>_id_idx.parquet` and live alongside the dataset Parquet directory
