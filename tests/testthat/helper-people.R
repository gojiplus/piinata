# Contact details in plainly named columns and inside a free-text note.
people <- function() {
  data.frame(
    id = 1:40,
    email = paste0("person", rep(1:20, 2), "@example.org"),
    phone = sprintf("98765%05d", rep(1:20, 2)),
    village = rep(c("Palpur", "Netrad"), 20),
    note = ifelse(1:40 %% 4 == 0, paste("Call me on", sprintf("98765%05d", 1:40), "after six"),
      "The road is bad after the rains"
    ),
    income = 2000 + 1:40
  )
}

# A project folder with a survey in csv and Stata, a log and files that
# cannot be redacted or need nothing.
project <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  readr::write_csv(people(), file.path(dir, "survey.csv"), na = "")
  data <- people()
  attr(data$email, "label") <- "Email address"
  data$village <- haven::labelled(match(data$village, c("Palpur", "Netrad")),
    c(Palpur = 1, Netrad = 2),
    label = "Village"
  )
  haven::write_dta(data, file.path(dir, "survey.dta"))
  writeLines(
    c("Started.", "Called 98765 43210 and 91234 56789; wrote to a@example.org.", "Done."),
    file.path(dir, "fieldwork.log")
  )
  writeLines("{\"email\": \"a@example.org\"}", file.path(dir, "contacts.json"))
  readr::write_csv(data.frame(season = rep(c("rabi", "kharif"), 20)), file.path(dir, "crops.csv"))
  dir
}

# A git repository holding two survey files.
repository <- function() {
  testthat::skip_if(!nzchar(Sys.which("git")), "git is not installed")
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  system2("git", c("init", "-q", shQuote(dir)))
  fs::dir_create(file.path(dir, "data"))
  readr::write_csv(people(), file.path(dir, "data", "survey.csv"), na = "")
  readr::write_csv(people(), file.path(dir, "data", "wave [2].csv"), na = "")
  dir
}

git_in <- function(dir, ...) {
  suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = FALSE))
}
