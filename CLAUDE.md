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

### Design decision: Rust-only, no pure-R fallback

`openalexSnapshot` is **Rust-only**. There is no pure-R/DuckDB fallback and none is planned.

**Rationale:** Maintaining two implementations (Rust + R) in parallel doubles the maintenance
burden and invites subtle divergence. The historical motivation for pure-R fallbacks was Rust
toolchain installation friction at the user's machine — that problem is solved at the distribution
layer instead:

- **r-universe** (or GitHub Actions) pre-compiles binaries for macOS (arm64 + x86_64), Linux
  (x86_64), and Windows before each release.
- Users install with `pak::pak("rkrug/openalexSnapshot")` and receive a pre-built binary — no
  Cargo required.
- Only package developers and CI need Rust installed.

The pure-R `_R` variants from openalexPro are available in git history if ever needed as
reference:
```
git -C ~/GitHub/openalexPro show 70539a0:R/snapshot_to_parquet.R
git -C ~/GitHub/openalexPro show 70539a0:R/build_corpus_index.R
git -C ~/GitHub/openalexPro show 70539a0:R/lookup_by_id.R
```

### Current state (stubs)

All three functions currently raise "not yet implemented" errors. They have the correct argument
signatures (preserved from openalexPro). The Rust back-end still needs to be wired up via
extendr.

### Rust back-end (openalex-core)

`~/GitHub/openalex-snapshot/src/main.rs` contains the Rust implementation. The key functions:
- `snapshot_to_parquet` — JSON.GZ → Parquet per dataset (schema inference + rayon parallelism)
- `build_corpus_index` — two-stage indexing (per-file shards → combined index)
- `lookup_by_id` — ID routing via entity prefix (`W`=works, `A`=authors, etc.)

To expose these via extendr:
1. Extract the relevant logic from `src/main.rs` into a Rust library crate under
   `~/GitHub/openalex-snapshot/` (or a separate `openalex-core` crate).
2. Add `src/rust/` to this R package with a thin extendr wrapper crate that depends on
   `openalex-core` and annotates the public functions with `#[extendr]`.
3. Add `src/Makevars.in` / `src/Makevars.win.in` and `configure` / `configure.win` via
   `rextendr::use_extendr()`.
4. Set up GitHub Actions to cross-compile and push to r-universe.

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
