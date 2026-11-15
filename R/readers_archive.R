archive_extensions <- c("zip", "kmz", "tar", "tgz", "tbz2", "txz")

# Members are read from a temporary copy, at most this deep. An archive that
# would unpack to more than `piinata.max_unpacked` bytes (2 GB unless the
# option says otherwise) is reported rather than unpacked: a zip by the sizes
# it lists, anything compressed by counting bytes as they are decompressed.
max_depth <- 3L

unpack_limit <- function() getOption("piinata.max_unpacked", 2e9)

size_label <- function(bytes) {
  if (bytes >= 1e9) {
    paste(format(bytes / 1e9, digits = 3), "GB")
  } else if (bytes >= 1e6) {
    paste(format(bytes / 1e6, digits = 3), "MB")
  } else {
    paste(format(bytes), "bytes")
  }
}

too_large <- function() {
  message <- paste("unpacks to more than", size_label(unpack_limit()))
  rlang::abort(message, class = "piinata_too_large")
}

# R's connections decompress gzip, bzip2 and xz alike; the copy stops as soon
# as it passes the limit.
decompress <- function(path, to) {
  input <- gzfile(path, "rb")
  on.exit(close(input))
  output <- file(to, "wb")
  on.exit(close(output), add = TRUE)
  written <- 0
  repeat {
    chunk <- readBin(input, "raw", 1e6)
    if (length(chunk) == 0L) break
    written <- written + length(chunk)
    if (written > unpack_limit()) too_large()
    writeBin(chunk, output)
  }
  invisible(to)
}

unpack <- function(path, kind, into) {
  if (kind == "zip") {
    if (sum(utils::unzip(path, list = TRUE)$Length) > unpack_limit()) too_large()
    utils::unzip(path, exdir = into)
  } else if (kind == "tar") {
    plain <- path
    if (!grepl("\\.tar$", tolower(path))) {
      plain <- tempfile(fileext = ".tar")
      on.exit(unlink(plain))
      decompress(path, plain)
    }
    if (file.size(plain) > unpack_limit()) too_large()
    utils::untar(plain, exdir = into)
  } else {
    decompress(path, file.path(into, fs::path_ext_remove(basename(path))))
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
read_archive <- function(path, registry, ignore, depth = 1L, root = ".") {
  failed <- function(status, detail) {
    list(list(source = path, fields = new_fields(), status = status, detail = detail))
  }
  if (depth > max_depth) {
    return(failed("unsupported", "archives nested more than three deep"))
  }
  kind <- archive_kind(path)
  into <- tempfile("piinata-")
  on.exit(unlink(into, recursive = TRUE), add = TRUE)
  fs::dir_create(into)
  unpacked <- tryCatch(unpack(path, kind, into), error = function(e) e)
  if (inherits(unpacked, "piinata_too_large")) {
    return(failed("unsupported", conditionMessage(unpacked)))
  }
  if (inherits(unpacked, "error")) {
    return(failed("failed", conditionMessage(unpacked)))
  }
  members <- as.character(fs::dir_ls(into, recurse = TRUE, type = "file"))
  if (length(members) == 0L) {
    return(failed("read", NA_character_))
  }
  inside <- paste0(path, "!", as.character(fs::path_rel(members, into)))
  results <- lapply(seq_along(members), function(i) {
    if (matches_glob(inside[i], ignore, root)) {
      return(list(list(
        source = inside[i], fields = new_fields(), status = "ignored",
        detail = "listed under ignore"
      )))
    }
    read_path(members[i], registry, ignore, depth + 1L, shown = inside[i], root = root)
  })
  unlist(results, recursive = FALSE)
}

# One file, or every member of an archive, read and named as `shown`.
read_path <- function(path, registry, ignore, depth = 1L, shown = path, root = ".") {
  if (file_type(path) == "archive") {
    results <- read_archive(path, registry, ignore, depth, root)
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
