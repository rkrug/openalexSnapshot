# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Package Does

**openalexSnapshot** is an R package for working with the [OpenAlex](https://openalex.org) bulk
snapshot. It handles the large-scale, offline data pipeline:

1. **`snapshot_to_parquet()`** — converts `.json.gz` snapshot files to Parquet (schema inference
   + parallel conversion)
2. **`build_corpus_index()`** — builds `<dataset>_id_idx/` ID-lookup indexes over the
   Parquet corpus
3. **`lookup_by_id()`** — extracts records by OpenAlex ID using the index

These functions were split out of **openalexPro** (v0.10.0). Calling them in `openalexPro` raises
an informative error pointing users here.

## Architecture

### Design decision: pure R

`openalexSnapshot` is **pure R** over DuckDB and arrow. There is no compiled
code, and no Rust toolchain is needed to install it.

It was previously a thin R layer over a compiled `openalex-core` crate. That
was removed once measurement showed it bought nothing on this workload: Part 4
of `../compatibility_report.md` found `index` and `extract` are parquet decode
and write rather than computation -- a single DuckDB thread already saturates,
so throughput was identical at 1 thread and at 8 -- putting the expected Rust
advantage at ~1.0-1.5x, and less on an external volume where cold I/O dominates
and is language-neutral.

Two things then made R the *better* implementation rather than merely the
adequate one:

* it writes a **sorted** index, which is what lets `lookup_by_id()` prune row
  groups instead of scanning a multi-GB file (measured: 1.87 s per call against
  an unsorted 7.29 GB works index);
* it supports `columns` (projection) and `add_columns`, neither of which the
  compiled path could do -- it always did `SELECT *`.

`snapshot_to_parquet()` was removed outright: OpenAlex now publishes the
snapshot natively in parquet, so JSON conversion is a dead path.

`backend` survives only as an argument that raises an explanatory error on
`"rust"`, so existing calls fail with a reason rather than "unused argument".

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
  - `<dataset>_doi_idx.parquet` — a single sorted **file**
  - `<dataset>_id_idx/` and `<dataset>_cite_idx/` — hive **directories**, partitioned
    by `id_block` / `cited_block` at `block_size = 1e7`. Directories because a
    single file needs a global sort to build and carries a footer that must be
    parsed on every query: the old one-file id index had 3,992 row groups and
    cost 0.192 s to open before reading any data. Blocks sort independently, and
    a lookup opens only the blocks its ids fall in.
- Indexes are written **sorted**, and this is load-bearing rather than tidy:
  `<dataset>_id_idx/` per block by `id`, `<dataset>_doi_idx.parquet`
  by `doi`, each `cite_idx` partition by `(cited_id, citing_id)`. Sorting is
  what lets a lookup prune row groups from footer statistics instead of
  scanning the file -- unsorted, the 7.29 GB works index cost 1.87 s per call.
  Every such write needs `preserve_insertion_order = TRUE`, or the parallel
  writer may reorder row groups and the ordering is silently lost.
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
