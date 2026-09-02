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

### Design decision: pure R by default, Rust as an optional accelerator

`openalexSnapshot` is moving to a **pure-R/DuckDB** implementation, with the compiled Rust
back-end retained as an optional accelerator. This reverses the earlier "Rust-only, no pure-R
fallback" position; see Part 4 of `../compatibility_report.md` for the measurement that drove
the change.

**Rationale (measured, not assumed).** For `index` and `extract` the work is parquet decode
and write, not computation — a single DuckDB thread already saturates the pipeline, so Rust's
expected advantage is ~1.0-1.5x and the real corpus lives on an external volume where cold I/O
dominates and is language-neutral. `enrich` was the one place Rust genuinely paid off (~10x),
and moving enrichment from download-time to extract-time removes that step in batch form
entirely. Dropping the Rust *requirement* also removes the toolchain dependency, restores a
realistic CRAN path, and eliminates the `openalex-core` git-tag pinning problem.

**Mechanism.** `build_corpus_index()` and `lookup_by_id()` take
`backend = c("auto", "r", "rust")`:

| value | behaviour |
|---|---|
| `"auto"` (default) | Rust when the compiled library is loaded, otherwise R |
| `"r"` | pure R/DuckDB — always available, and what CI exercises |
| `"rust"` | force the compiled path; errors if it is not loaded |

| function | R backend | Rust backend |
|---|---|---|
| `build_corpus_index()` | yes | yes |
| `lookup_by_id()` | yes | yes |
| `snapshot_to_parquet()` | **no** | yes (only) |
| `build_citation_index()`, `build_doi_index()`, `get_citing()`, `get_cited()`, `doi_to_id()`, `lookup_by_doi()` | **yes (only)** | no |

`snapshot_to_parquet()` stays Rust-only deliberately: it is the hardest to port (JSON schema
inference), it is not on the critical path for the offline citation graph, and the official
OpenAlex snapshot is now published natively in parquet, so JSON conversion is a legacy path.

The pure-R implementations that seeded this work are in openalexPro's git history:
```
git -C ~/GitHub/openalexPro show 70539a0:R/build_corpus_index.R
git -C ~/GitHub/openalexPro show 70539a0:R/lookup_by_id.R
git -C ~/GitHub/openalexPro show 70539a0:R/snapshot_to_parquet.R
```

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

- Work on `claude/<description>` branches from **`dev`**; merge back into `dev`
- `main` receives release commits; never commit to it directly
- `main` and `dev` are long-lived; do not delete `dev` after a PR merge

## Key Conventions

- `root_dir` is the standard top-level directory parameter (consistent with openalexPro's
  `project_dir` convention for API work)
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form
  (`https://openalex.org/W2741809807`)
- Index files live alongside the dataset Parquet directory. Two shapes:
  - `<dataset>_id_idx.parquet`, `<dataset>_doi_idx.parquet` — single sorted **files**
  - `<dataset>_cite_idx/` — a hive **directory** partitioned by `cited_block`. It is a
    directory because a 3-billion-row single file cannot be built without a global sort and
    its footer alone would cost tens of MB to parse on every query
- `cited_block = floor(numeric_id / 1e7)` (i.e. `id_block(x) %/% 1000L`) — ~351 partitions.
  Plain `id_block()`'s `floor(n/1e4)` would give 714k partitions and is unusable as a
  partition key. `block_size` is recorded in `_index_meta.parquet` and must be **read from
  there**, never assumed
- `_index_meta.parquet` is written **last** by an index builder; its presence is the
  "this index is complete" signal
- `add_columns` values are embedded as **single-quoted SQL string literals**, matching
  `openalexPro::pro_request_parquet()`. That is why `oa_input` round-trips as VARCHAR and is
  cast to BOOLEAN at node-assembly time — it lets openalexSnowball share one assembly step
  across the API and snapshot paths
- DOI keys are normalised with the internal `.oas_normalize_doi()` (strip resolver, lowercase,
  trim), **not** `openalexPro::extract_doi()`. The latter is an extractor, not a normaliser: it
  returns a substring of a wrong input rather than failing. openalexSnapshot also takes no
  openalexPro dependency, deliberately — it is the offline half of the ecosystem and must not
  pull in httr2/curl/jqr
- `referenced_works` is `VARCHAR[]` in the official parquet but a JSON `VARCHAR` in the legacy
  converted corpus. Sniff the type in R (a SQL `CASE WHEN typeof(...)` will not bind) and use
  `json_extract_string(x, '$[*]')` for the JSON form
