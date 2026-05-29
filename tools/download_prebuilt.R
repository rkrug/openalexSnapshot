## tools/download_prebuilt.R
##
## Called by `configure` before `tools/config.R`.
## Downloads the pre-compiled libopenalexSnapshot.a for the current platform
## from the versioned GitHub Release in the openalex-snapshot (Rust core) repo
## and writes it to `src/prebuilt/libopenalexSnapshot.a`.
##
## The release tag is derived automatically from the `openalex-core` git
## dependency tag pinned in `src/rust/Cargo.toml` (e.g. "v0.5.0"), ensuring
## the prebuilt binary always matches the core version in use.
##
## If the download succeeds, config.R / Makevars.in will use the prebuilt
## binary and skip `cargo build` entirely (~2 min vs ~50 min).
##
## Opt-out: set OPENALEXSNAPSHOT_BUILD_FROM_SOURCE=true to force compilation.
## Override tag:  set OPENALEXSNAPSHOT_PREBUILT_RELEASE=v0.5.0

## ---- configuration ---------------------------------------------------------

## Prebuilt libs are published by openalex-snapshot (the Rust core repo) on
## each versioned release.  The tag to download is read from the pinned
## `openalex-core` git dependency in src/rust/Cargo.toml so it always matches
## the exact core version this R package was built against.

REPO     <- "rkrug/openalex-snapshot"   # Rust core repo; update after org transfer
DEST_DIR  <- file.path("src", "prebuilt")
DEST_FILE <- file.path(DEST_DIR, "libopenalexSnapshot.a")

## Determine the release tag: env-var override → parse Cargo.toml → give up
get_release_tag <- function() {
  override <- Sys.getenv("OPENALEXSNAPSHOT_PREBUILT_RELEASE", "")
  if (nzchar(override)) return(override)

  cargo_toml <- file.path("src", "rust", "Cargo.toml")
  if (!file.exists(cargo_toml)) {
    message("[prebuilt] src/rust/Cargo.toml not found — cannot determine release tag.")
    return(NULL)
  }
  lines <- readLines(cargo_toml, warn = FALSE)
  tag_lines <- grep('tag\\s*=\\s*"v', lines, value = TRUE)
  if (length(tag_lines) == 0) {
    message("[prebuilt] No tag = \"v...\" found in Cargo.toml — cannot determine release tag.")
    return(NULL)
  }
  m <- regmatches(tag_lines[[1]], regexpr('v[0-9]+\\.[0-9]+\\.[0-9]+[^"]*', tag_lines[[1]]))
  if (length(m) == 0) return(NULL)
  m
}

RELEASE <- get_release_tag()
if (is.null(RELEASE)) quit(status = 0)   # non-fatal: configure continues to config.R

## ---- opt-out ---------------------------------------------------------------

if (nzchar(Sys.getenv("OPENALEXSNAPSHOT_BUILD_FROM_SOURCE"))) {
  message("[prebuilt] OPENALEXSNAPSHOT_BUILD_FROM_SOURCE set — skipping download.")
  quit(status = 0)
}

## ---- platform → target triple ----------------------------------------------

get_target <- function() {
  sysname <- Sys.info()[["sysname"]]
  arch    <- R.version$arch

  if (.Platform$OS.type == "windows") {
    return("x86_64-pc-windows-gnu")
  }

  if (sysname == "Darwin") {
    if (grepl("aarch64|arm64", arch)) return("aarch64-apple-darwin")
    return("x86_64-apple-darwin")
  }

  # Linux / other Unix
  if (grepl("x86_64|amd64", arch)) return("x86_64-unknown-linux-gnu")
  if (grepl("aarch64|arm64", arch)) return("aarch64-unknown-linux-gnu")

  warning("[prebuilt] Unrecognised platform arch '", arch, "' — will compile from source.")
  return(NULL)
}

target <- get_target()
if (is.null(target)) quit(status = 0)

## ---- build download URL ----------------------------------------------------

artifact <- paste0("libopenalexSnapshot-", target, ".a")
url <- paste0(
  "https://github.com/", REPO,
  "/releases/download/", RELEASE, "/", artifact
)

message("[prebuilt] Attempting to download prebuilt lib for ", target, " ...")
message("[prebuilt] URL: ", url)

## ---- download --------------------------------------------------------------

dir.create(DEST_DIR, showWarnings = FALSE, recursive = TRUE)

result <- tryCatch(
  download.file(url, DEST_FILE, quiet = FALSE, mode = "wb"),
  error   = function(e) { message("[prebuilt] Download error: ", conditionMessage(e)); 1L },
  warning = function(w) { message("[prebuilt] Download warning: ", conditionMessage(w)); 1L }
)

if (!identical(result, 0L) || !file.exists(DEST_FILE) || file.size(DEST_FILE) < 1000L) {
  message("[prebuilt] Download failed or file too small — will compile from source.")
  unlink(DEST_FILE)
  quit(status = 0)   # non-fatal: configure continues to config.R
}

message("[prebuilt] Prebuilt lib saved to ", DEST_FILE,
        " (", round(file.size(DEST_FILE) / 1e6, 1), " MB)")
