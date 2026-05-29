## tools/download_prebuilt.R
##
## Called by `configure` before `tools/config.R`.
## Downloads the pre-compiled libopenalexSnapshot.a for the current platform
## from the `prebuilt-libs` GitHub Release and writes it to
## `src/prebuilt/libopenalexSnapshot.a`.
##
## If the download succeeds, config.R / Makevars.in will use the cached binary
## and skip `cargo build` entirely (~2 min vs ~40 min).
##
## Opt-out: set OPENALEXSNAPSHOT_BUILD_FROM_SOURCE=true to force compilation.

## ---- configuration ---------------------------------------------------------

REPO      <- "rkrug/openalexSnapshot"   # update after org transfer
RELEASE   <- Sys.getenv("OPENALEXSNAPSHOT_PREBUILT_RELEASE", "prebuilt-libs")
DEST_DIR  <- file.path("src", "prebuilt")
DEST_FILE <- file.path(DEST_DIR, "libopenalexSnapshot.a")

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
