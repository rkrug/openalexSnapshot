[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20448992.svg)](https://doi.org/10.5281/zenodo.20448992)

<!-- README.md is generated from README.Rmd. Please edit that file -->

# openalexSnapshot

<!-- badges: start -->
[![r-universe](https://rkrug.r-universe.dev/badges/openalexSnapshot)](https://rkrug.r-universe.dev/openalexSnapshot)
[![Codecov test coverage](https://codecov.io/gh/openalexPro/openalexSnapshot/graph/badge.svg)](https://app.codecov.io/gh/openalexPro/openalexSnapshot)
<!-- badges: end -->

`openalexSnapshot` converts the [OpenAlex bulk
snapshot](https://docs.openalex.org/download-all-data/openalex-snapshot)
from gzipped newline-delimited JSON to Parquet, builds fast ID-lookup
indexes, and extracts individual records by OpenAlex ID. The heavy
lifting is done by a compiled Rust library (statically linked via
[extendr](https://extendr.github.io/)), with no external binary
dependency. For API-based access to OpenAlex, see
[openalexPro](https://openalexpro.github.io/openalexPro).

## Installation

Install from r-universe (precompiled binaries available for macOS and
Linux — no Rust toolchain required):

``` r
install.packages(
  "openalexSnapshot",
  repos = c("https://rkrug.r-universe.dev", "https://cloud.r-project.org")
)
```

Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("openalexPro/openalexSnapshot")
```

## Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Disk space | 2.5 TB | 3+ TB |
| RAM | 16 GB | 32+ GB |
| CPU | 2 cores | 4+ cores |

## Quick Start

``` r
library(openalexSnapshot)

root <- "/Volumes/openalex"

# 1. Convert the snapshot to Parquet
snapshot_to_parquet(
  root_dir     = root,
  workers      = 4,
  memory_limit = 15000   # MB
)

# 2. Build ID indexes
build_corpus_index(
  root_dir  = root,
  data_sets = "works",
  workers   = 4
)

# 3. Look up specific records by OpenAlex ID
out_dir <- file.path(root, "my_extract")
lookup_by_id(
  index_file = file.path(root, "parquet", "works_id_idx.parquet"),
  ids        = c("W2741809807", "W2100837269"),
  output_dir = out_dir
)

# 4. Read results
library(arrow)
works <- open_dataset(out_dir) |> collect()
```

## Documentation

Full documentation and articles are available at
<https://openalexpro.github.io/openalexSnapshot>.

- [Working with the OpenAlex Bulk
  Snapshot](https://openalexpro.github.io/openalexSnapshot/articles/snapshot-workflow.html)
  — download, convert, index, and query the full snapshot
- [Snapshot Conversion: From JSON to
  Parquet](https://openalexpro.github.io/openalexSnapshot/articles/snapshot-conversion.html)
  — detailed function reference

## Related packages

- [openalexPro](https://openalexpro.github.io/openalexPro) — API access,
  tidy data frames, and advanced OpenAlex workflows
