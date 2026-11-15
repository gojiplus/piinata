types_in <- function(path) {
  findings <- pii_scan(path, config = pii_config("none.yml"))
  sort(unique(findings$type[findings$confidence != "low"]))
}

test_that("archives are read member by member and named inside", {
  skip_if(!nzchar(Sys.which("zip")), "zip is not installed")
  dir <- withr::local_tempdir()
  readr::write_csv(survey(), file.path(dir, "survey.csv"))
  writeLines("Called 98765 43210; mail asha@example.org", file.path(dir, "notes.txt"))
  writeLines("not data", file.path(dir, "readme.xyz"))
  withr::with_dir(dir, utils::zip("delivery.zip", c("survey.csv", "notes.txt", "readme.xyz"),
    flags = "-q"
  ))
  fields <- pii_read(file.path(dir, "delivery.zip"))
  report <- pii_read_report(fields)
  members <- basename(sub(".*!", "", report$source))
  expect_setequal(members, c("survey.csv", "notes.txt", "readme.xyz"))
  expect_true(all(grepl("delivery.zip!", report$source, fixed = TRUE)))
  expect_equal(report$status[grepl("readme", report$source)], "unsupported")
  expect_true("email" %in% pii_scan(fields)$type)
})

test_that("tar archives and nested archives are read", {
  dir <- withr::local_tempdir()
  inner <- file.path(dir, "inner")
  fs::dir_create(inner)
  writeLines("Mail asha@example.org", file.path(inner, "notes.txt"))
  withr::with_dir(dir, utils::tar("inner.tar.gz", "inner", compression = "gzip"))
  withr::with_dir(dir, utils::tar("outer.tar", "inner.tar.gz"))
  report <- pii_read_report(pii_read(file.path(dir, "outer.tar")))
  expect_equal(report$status, "read")
  expect_match(report$source, "outer.tar!inner.tar.gz!inner/notes.txt", fixed = TRUE)
})

test_that("an archive member can be ignored by its name inside", {
  skip_if(!nzchar(Sys.which("zip")), "zip is not installed")
  dir <- withr::local_tempdir()
  writeLines("Mail asha@example.org", file.path(dir, "notes.txt"))
  withr::with_dir(dir, utils::zip("a.zip", "notes.txt", flags = "-q"))
  report <- pii_read_report(pii_read(file.path(dir, "a.zip"), ignore = "*!notes.txt"))
  expect_equal(report$status, "ignored")
})

test_that("notebook outputs are scanned", {
  skip_if_not_installed("jsonlite")
  path <- withr::local_tempfile(fileext = ".ipynb")
  notebook <- list(cells = list(list(
    cell_type = "code", source = list("df.head()"),
    outputs = list(list(data = list(`text/plain` = list(
      "   name             email", "0  Asha Devi   asha@example.org"
    ))))
  )))
  jsonlite::write_json(notebook, path, auto_unbox = TRUE)
  fields <- pii_read(path)
  expect_equal(fields$locator, "cell 1")
  expect_true("email" %in% types_in(path))
})

test_that("contact cards are read as text", {
  path <- withr::local_tempfile(fileext = ".vcf")
  writeLines(c(
    "BEGIN:VCARD", "FN:Asha Devi", "TEL:+91 98765 43210", "EMAIL:asha@example.org", "END:VCARD"
  ), path)
  expect_true(all(c("email", "phone") %in% types_in(path)))
})

points <- function(n = 30) {
  data.frame(
    household = paste("HH", seq_len(n)), longitude = 75 + seq_len(n) / 1000,
    latitude = 26 + seq_len(n) / 1000
  )
}

test_that("GeoJSON points give coordinates and attributes", {
  skip_if_not_installed("jsonlite")
  data <- points()
  features <- lapply(seq_len(nrow(data)), function(i) {
    list(
      type = "Feature", properties = list(head_name = paste("Asha", i)),
      geometry = list(type = "Point", coordinates = c(data$longitude[i], data$latitude[i]))
    )
  })
  path <- withr::local_tempfile(fileext = ".geojson")
  jsonlite::write_json(list(type = "FeatureCollection", features = features), path,
    auto_unbox = TRUE, digits = NA
  )
  fields <- pii_read(path)
  expect_setequal(fields$name, c("head_name", "longitude", "latitude"))
  expect_true("coordinates" %in% types_in(path))
})

test_that("KML placemarks give coordinates", {
  skip_if_not_installed("xml2")
  data <- points()
  marks <- sprintf(
    paste0(
      "<Placemark><name>HH %d</name>",
      "<Point><coordinates>%.4f,%.4f,0</coordinates></Point></Placemark>"
    ),
    seq_len(nrow(data)), data$longitude, data$latitude
  )
  path <- withr::local_tempfile(fileext = ".kml")
  writeLines(c(
    "<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>", marks, "</Document></kml>"
  ), path)
  expect_true("coordinates" %in% types_in(path))
})

test_that("shapefiles give coordinates, attributes, and quiet side files", {
  skip_if_not_installed("sf")
  skip_if_not_installed("foreign")
  dir <- withr::local_tempdir()
  data <- points()
  data$head_name <- paste("Asha Devi", seq_len(nrow(data)))
  shapes <- sf::st_as_sf(data, coords = c("longitude", "latitude"), crs = 4326)
  sf::st_write(shapes, file.path(dir, "households.shp"), quiet = TRUE)
  report <- pii_read_report(pii_read(dir))
  expect_true(all(report$status[grepl("\\.(shx|prj|cpg)$", report$source)] == "ignored"))
  expect_true("coordinates" %in% types_in(file.path(dir, "households.shp")))
  expect_true("head_name" %in% pii_read(file.path(dir, "households.dbf"))$name)
})

test_that("SQLite tables are read, and other .db files are not mistaken for them", {
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("DBI")
  path <- withr::local_tempfile(fileext = ".sqlite")
  connection <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(connection, "respondents", survey())
  DBI::dbDisconnect(connection)
  fields <- pii_read(path)
  expect_true(all(startsWith(fields$locator, "respondents!")))
  expect_true("email" %in% types_in(path))
  other <- withr::local_tempfile(fileext = ".db")
  writeLines("not a database", other)
  expect_equal(pii_read_report(pii_read(other))$status, "unsupported")
})

test_that("OpenDocument spreadsheets and PowerPoint files are read", {
  skip_if_not_installed("readODS")
  path <- withr::local_tempfile(fileext = ".ods")
  readODS::write_ods(survey(), path)
  expect_true("email" %in% types_in(path))
  skip_if_not_installed("officer")
  deck <- withr::local_tempfile(fileext = ".pptx")
  slides <- officer::add_slide(officer::read_pptx(), layout = "Title and Content")
  body <- officer::ph_location_type("body")
  slides <- officer::ph_with(slides, "Contact asha@example.org", location = body)
  print(slides, target = deck)
  expect_equal(pii_read(deck)$locator, "slide 1")
  expect_true("email" %in% types_in(deck))
})

test_that("legacy Word files are reported, not skipped", {
  path <- withr::local_tempfile(fileext = ".doc")
  writeLines("binary", path)
  report <- pii_read_report(pii_read(path))
  expect_equal(report$status, "unsupported")
  expect_match(report$detail, "docx")
})
