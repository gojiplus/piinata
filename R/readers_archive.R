archive_extensions <- c("zip", "kmz", "tar", "tgz", "tbz2", "txz")

# Members are read from a temporary copy, at most this deep, and an archive
# that would unpack to more than `max_unpacked` bytes is reported rather than
# unpacked.
max_depth <- 3L
max_unpacked <- 2e9

unpacked_size <- function(path, kind) {
  if (kind == "zip") {
    return(sum(utils::unzip(path, list = TRUE)$Length))
  }
  NA_real_
}

unpack <- function(path, kind, into) {
  if (kind == "zip") {
    utils::unzip(path, exdir = into)
  } else if (kind == "tar") {
    utils::untar(path, exdir = into)
  } else {
    # A single compressed file, such as survey.dta.gz: R's connections
    # decompress gzip, bzip2 and xz alike.
    inner <- file.path(into, fs::path_ext_remove(basename(path)))
    input <- gzfile(path, "rb")
    on.exit(close(input))
    output <- file(inner, "wb")
    on.exit(close(output), add = TRUE)
    repeat {
      chunk <- readBin(input, "raw", 1e6)
      if (length(chunk) == 0L) break
      writeBin(chunk, output)
    }
  }
  invisible(into)
}

archive_kind <- function(path) {
  name <- tolower(basename(path))
  if (grepl("\\.(zip|kmz)$", name)) {
    "zip"
  } else if (grepl("\\.(tar|tgz|tbz2|txz)$|\\.tar\\.(gz|bz2|xz)$", name)) {
    "tar"
  } else {
    "single"
  }
}

# Reads every member of an archive as if it were a file, and names each one
# `archive!member` so findings point inside the archive.
read_archive <- function(path, registry, ignore, depth = 1L) {
  failed <- function(status, detail) {
    list(list(source = path, fields = new_fields(), status = status, detail = detail))
  }
  if (depth > max_depth) {
    return(failed("unsupported", "archives nested more than three deep"))
  }
  kind <- archive_kind(path)
  size <- tryCatch(unpacked_size(path, kind), error = function(e) NA_real_)
  if (!is.na(size) && size > max_unpacked) {
    return(failed("unsupported", "unpacks to more than 2 GB"))
  }
  into <- tempfile("piinata-")
  on.exit(unlink(into, recursive = TRUE), add = TRUE)
  fs::dir_create(into)
  unpacked <- tryCatch(unpack(path, kind, into), error = function(e) e)
  if (inherits(unpacked, "error")) {
    return(failed("failed", conditionMessage(unpacked)))
  }
  members <- as.character(fs::dir_ls(into, recurse = TRUE, type = "file"))
  if (length(members) == 0L) {
    return(failed("read", NA_character_))
  }
  inside <- paste0(path, "!", as.character(fs::path_rel(members, into)))
  results <- lapply(seq_along(members), function(i) {
    if (matches_glob(inside[i], ignore)) {
      return(list(list(
        source = inside[i], fields = new_fields(), status = "ignored",
        detail = "listed under ignore"
      )))
    }
    read_path(members[i], registry, ignore, depth + 1L, shown = inside[i])
  })
  unlist(results, recursive = FALSE)
}

# One file, or every member of an archive, read and named as `shown`.
read_path <- function(path, registry, ignore, depth = 1L, shown = path) {
  if (file_type(path) == "archive") {
    results <- read_archive(path, registry, ignore, depth)
    return(lapply(results, function(r) {
      r$source <- sub(path, shown, r$source, fixed = TRUE)
      r$fields$source <- sub(path, shown, r$fields$source, fixed = TRUE)
      r
    }))
  }
  result <- read_one(path, registry)
  result$fields$source <- rep(shown, nrow(result$fields))
  list(c(list(source = shown), result))
}
