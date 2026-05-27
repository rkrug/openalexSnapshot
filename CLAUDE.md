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

`~/GitHub/openalex-snapshot/openalex-core/` is already a **library crate** in the workspace,
explicitly designed to be called from R. Its `conversion` feature exposes exactly the three
functions this package needs:

```
openalex-core/src/conversion.rs
  pub fn snapshot_to_parquet(...)   line 258
  pub fn build_corpus_index(...)    line 786
  pub fn lookup_by_id(...)          line 991
  pub fn infer_api_list_type(...)   line 610  (used by openalexPro's pro_request_parquet)
```

`openalex-core/src/lib.rs` also re-exports `works_abstract_expr()` and `works_citation_expr()`
(the SQL helpers now duplicated in `openalexPro/R/sql_helpers.R`).

**Steps to wire up the extendr bridge:**

1. `rextendr::use_extendr()` — adds `src/rust/` scaffolding to this R package.
2. Write `src/rust/src/lib.rs`: a thin crate that depends on `openalex-core` with
   `features = ["conversion"]` and wraps the pub functions with `#[extendr]`.
3. In `src/rust/Cargo.toml`, point to openalex-core via a path or git dependency:
   ```toml
   [dependencies]
   openalex-core = { path = "../../../../openalex-snapshot/openalex-core", features = ["conversion"] }
   extendr-api = "*"
   ```
4. The `configure` / `configure.win` scripts from the old openalexPro extendr bridge are
   recoverable from git history:
   ```
   git -C ~/GitHub/openalexPro show c86725f:configure
   git -C ~/GitHub/openalexPro show c86725f:configure.win
   ```
5. Set up GitHub Actions cross-compilation and r-universe publishing.

**Important:** `openalex-core` lives in a Cargo workspace. When building as a dependency from
this R package's `src/rust/` crate, the workspace root must be discoverable or the dependency
must be referenced via a published crate on crates.io / git URL (not a relative path that
crosses the workspace boundary). The cleanest solution is to publish `openalex-core` to
crates.io, or reference it via a git URL with `tag = "vX.Y.Z"`.

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
