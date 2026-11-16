test_that("originals are ignored and their redacted copies are not", {
  dir <- repository()
  report <- suppressMessages(pii_redact_files(file.path(dir, "data")))
  ignored <- suppressMessages(pii_ignore_originals(report))
  expect_equal(ignored$action, c("added", "added"))
  expect_false(any(ignored$is_tracked))
  status <- git_in(dir, "status", "--porcelain", "--untracked-files=all")
  expect_true(any(grepl("survey_redacted.csv", status, fixed = TRUE)))
  expect_true(any(grepl("wave [2]_redacted.csv", status, fixed = TRUE)))
  expect_false(any(grepl("data/survey.csv", status, fixed = TRUE)))
  expect_false(any(grepl("data/wave [2].csv", status, fixed = TRUE)))
})

test_that("a second run adds nothing", {
  dir <- repository()
  report <- suppressMessages(pii_redact_files(file.path(dir, "data")))
  suppressMessages(pii_ignore_originals(report))
  before <- readLines(file.path(dir, ".gitignore"))
  again <- suppressMessages(pii_ignore_originals(report))
  expect_equal(again$action, c("already ignored", "already ignored"))
  expect_equal(readLines(file.path(dir, ".gitignore")), before)
})

test_that("an original already committed is reported as tracked", {
  dir <- repository()
  git_in(dir, "add", "data/survey.csv")
  git_in(dir, "-c", "user.name=t", "-c", "user.email=t@example.org", "commit", "-q", "-m", "x")
  report <- suppressMessages(pii_redact_files(file.path(dir, "data", "survey.csv")))
  ignored <- suppressMessages(pii_ignore_originals(report))
  expect_true(ignored$is_tracked)
  expect_match(ignored$detail, "git rm --cached")
})

test_that("a copy hidden by an existing rule is reported", {
  dir <- repository()
  writeLines("*.csv", file.path(dir, ".gitignore"))
  report <- suppressMessages(pii_redact_files(file.path(dir, "data", "survey.csv")))
  ignored <- suppressMessages(pii_ignore_originals(report))
  expect_equal(ignored$action, "already ignored")
  expect_match(ignored$detail, "is ignored too")
})

test_that("files outside a repository are reported, not changed", {
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  dir <- withr::local_tempdir()
  readr::write_csv(people(), file.path(dir, "survey.csv"), na = "")
  report <- suppressMessages(pii_redact_files(dir))
  ignored <- suppressMessages(pii_ignore_originals(report))
  expect_equal(ignored$action, "not in a git repository")
  expect_false(fs::file_exists(file.path(dir, ".gitignore")))
})

test_that("the repository root does not depend on how git prints paths", {
  # Git built on MSYS, as on win-builder, prints the top level as /d/temp/...,
  # which R on Windows cannot open.
  dir <- repository()
  report <- suppressMessages(pii_redact_files(file.path(dir, "data")))
  real_git <- git
  local_mocked_bindings(git = function(root, ...) {
    if ("--show-toplevel" %in% c(...)) {
      return(list(ok = TRUE, out = "/d/temp/not-a-windows-path"))
    }
    real_git(root, ...)
  })
  ignored <- suppressMessages(pii_ignore_originals(report))
  expect_equal(ignored$action, c("added", "added"))
})
