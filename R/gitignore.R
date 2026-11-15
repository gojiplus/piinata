# Git is called on the command line, which every user of a repository has,
# rather than through 'gert', whose libgit2 the core does not otherwise need.
git <- function(root, ...) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), ...),
    stdout = TRUE, stderr = FALSE
  ))
  status <- attr(out, "status")
  list(ok = is.null(status) || status == 0L, out = out)
}

git_root <- function(path) {
  found <- git(fs::path_dir(path), "rev-parse", "--show-toplevel")
  if (found$ok && length(found$out) == 1L) as.character(fs::path_real(found$out)) else NA_character_
}

# A path written as a .gitignore rule that matches that file and nothing else:
# anchored at the root, with the characters gitignore treats specially escaped.
ignore_rule <- function(relative) {
  paste0("/", gsub("([][*?!#\\\\ ])", "\\\\\\1", relative))
}

is_ignored <- function(root, relative) {
  git(root, "check-ignore", "-q", "--no-index", "--", shQuote(relative))$ok
}

#' Keep the originals of redacted files out of git
#'
#' After [pii_redact_files()] has written a redacted copy beside each flagged
#' file, adds each original to its repository's `.gitignore`, so the clean
#' copy can be committed and the original cannot be by accident. Each rule
#' names one file. Every rule added is checked with `git check-ignore`, and a
#' redacted copy that an existing rule would also hide is reported.
#'
#' It does not rewrite history. An original already committed stays in the
#' repository's past, and stays tracked until removed with
#' `git rm --cached`; such files are reported as `tracked`.
#'
#' @param report The result of [pii_redact_files()].
#' @return A tibble with one row per redacted original: `source`, the
#'   `gitignore` file changed, the `action` taken (`added`, `already ignored`
#'   or `not in a git repository`), whether the original is `tracked`, and
#'   `detail`.
#' @export
#' @examples
#' \dontrun{
#' report <- pii_redact_files("data")
#' pii_ignore_originals(report)
#' }
pii_ignore_originals <- function(report) {
  if (!is.data.frame(report) || !all(c("source", "status", "destination") %in% names(report))) {
    cli::cli_abort("{.arg report} must be the result of {.fn pii_redact_files}.")
  }
  if (!nzchar(Sys.which("git"))) {
    cli::cli_abort("Cannot find {.code git}.")
  }
  done <- report[report$status %in% c("redacted", "partly redacted"), ]
  rows <- lapply(seq_len(nrow(done)), function(i) {
    ignore_original(done$source[i], done$destination[i])
  })
  empty <- tibble::tibble(
    source = character(), gitignore = character(), action = character(),
    tracked = logical(), detail = character()
  )
  result <- do.call(rbind, c(list(empty), rows))
  added <- result$source[result$action == "added"]
  tracked <- result$source[result$tracked %in% TRUE]
  cli::cli_inform(c(
    "Added {length(added)} original{?s} to {.file .gitignore}.",
    "!" = if (length(tracked) > 0L) {
      "{length(tracked)} {?is/are} already tracked; {.code git rm --cached} stops tracking,
       but the history keeps {?it/them}."
    }
  ))
  result
}

ignore_original <- function(source, destination) {
  row <- function(gitignore, action, tracked, detail = NA_character_) {
    tibble::tibble(
      source = source, gitignore = gitignore, action = action, tracked = tracked, detail = detail
    )
  }
  path <- as.character(fs::path_real(source))
  root <- git_root(path)
  if (is.na(root)) {
    return(row(NA_character_, "not in a git repository", NA))
  }
  relative <- as.character(fs::path_rel(path, root))
  gitignore <- file.path(root, ".gitignore")
  tracked <- git(root, "ls-files", "--error-unmatch", "--", shQuote(relative))$ok
  if (is_ignored(root, relative)) {
    action <- "already ignored"
  } else {
    lines <- if (fs::file_exists(gitignore)) readLines(gitignore, warn = FALSE) else character()
    header <- "# Originals holding personal data; redacted copies sit beside them (piinata)"
    new <- c(if (!header %in% lines) c(if (length(lines) > 0L) "", header), ignore_rule(relative))
    writeLines(c(lines, new), gitignore)
    if (!is_ignored(root, relative)) {
      cli::cli_abort("Added a rule for {.file {relative}} to {.file {gitignore}}, but git does not
                      ignore the file.")
    }
    action <- "added"
  }
  copy <- as.character(fs::path_rel(fs::path_real(destination), root))
  detail <- c(
    if (tracked) paste("still tracked; run: git rm --cached", shQuote(relative)),
    if (is_ignored(root, copy)) paste("the redacted copy", copy, "is ignored too")
  )
  detail <- if (length(detail) > 0L) paste(detail, collapse = "; ") else NA_character_
  row(gitignore, action, tracked, detail)
}
