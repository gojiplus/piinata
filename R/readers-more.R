# Readers for notebooks, geographic files, databases and office formats. Each
# uses a maintained package and turns what it reads into fields like any
# other reader.

ignore_file <- function(detail) {
  rlang::abort(detail, class = "piinata_ignored")
}

# A notebook's printed outputs often hold rows of the data it was run on.
read_notebook <- function(path) {
  need("jsonlite", "Jupyter notebooks")
  notebook <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  cells <- lapply(seq_along(notebook$cells), function(i) {
    cell <- notebook$cells[[i]]
    outputs <- unlist(lapply(cell$outputs, function(output) {
      c(unlist(output$text), unlist(output$data$`text/plain`))
    }))
    text <- unlist(strsplit(c(unlist(cell$source), outputs), "\n", fixed = TRUE))
    fields_from_text(text, path, paste("cell", i))
  })
  do.call(rbind, c(list(new_fields()), cells))
}

# The first coordinate pair of any geometry: a point's own, or the first
# vertex of a line or polygon, which is enough to place a household.
first_pair <- function(coordinates) {
  values <- suppressWarnings(as.numeric(unlist(coordinates)))
  if (length(values) < 2L) c(NA_real_, NA_real_) else values[1:2]
}

with_coordinates <- function(attributes, pairs) {
  attributes$longitude <- vapply(pairs, `[`, numeric(1), 1L)
  attributes$latitude <- vapply(pairs, `[`, numeric(1), 2L)
  attributes
}

read_geojson <- function(path) {
  need("jsonlite", "GeoJSON files")
  geo <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  features <- if (identical(geo$type, "FeatureCollection")) geo$features else list(geo)
  rows <- lapply(features, function(feature) {
    properties <- lapply(feature$properties, function(v) {
      if (is.null(v)) NA_character_ else paste(unlist(v), collapse = " ")
    })
    tibble::as_tibble(properties)
  })
  attributes <- if (length(rows) > 0L) bind_filled(rows) else tibble::tibble(.rows = 0L)
  pairs <- lapply(features, function(f) {
    first_pair(if (is.null(f$geometry)) f$coordinates else f$geometry$coordinates)
  })
  fields_from_table(with_coordinates(attributes, pairs), path)
}

# Binds rows whose columns differ, filling the gaps with NA.
bind_filled <- function(rows) {
  columns <- unique(unlist(lapply(rows, names)))
  filled <- lapply(rows, function(row) {
    row[setdiff(columns, names(row))] <- NA_character_
    row[columns]
  })
  do.call(rbind, filled)
}

read_kml <- function(path) {
  need("xml2", "KML files")
  document <- xml2::xml_ns_strip(xml2::read_xml(path))
  marks <- xml2::xml_find_all(document, ".//Placemark")
  text_of <- function(node, xpath) {
    found <- xml2::xml_find_first(node, xpath)
    if (inherits(found, "xml_missing")) NA_character_ else xml2::xml_text(found)
  }
  attributes <- tibble::tibble(
    name = vapply(marks, text_of, character(1), xpath = "./name"),
    description = vapply(marks, text_of, character(1), xpath = "./description")
  )
  pairs <- lapply(marks, function(mark) {
    first_pair(strsplit(trimws(text_of(mark, ".//coordinates")), "[,[:space:]]+"))
  })
  fields_from_table(with_coordinates(attributes, pairs), path)
}

read_dbf <- function(path) {
  fields_from_table(foreign::read.dbf(path, as.is = TRUE), path)
}

# Geometry needs 'sf'; the attribute table beside it is read from the .dbf.
read_shapefile <- function(path) {
  need("sf", "the geometry of shapefiles")
  shapes <- sf::st_read(path, quiet = TRUE)
  fields_from_table(geometry_coordinates(shapes), path)
}

geometry_coordinates <- function(shapes) {
  if (!is.na(sf::st_crs(shapes)) && !isTRUE(sf::st_is_longlat(shapes))) {
    shapes <- sf::st_transform(shapes, 4326)
  }
  points <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(shapes)))
  xy <- sf::st_coordinates(points)
  tibble::tibble(longitude = xy[, 1], latitude = xy[, 2])
}

read_geopackage <- function(path) {
  need("sf", "GeoPackage files")
  layers <- sf::st_layers(path)$name
  fields <- lapply(layers, function(layer) {
    shapes <- sf::st_read(path, layer = layer, quiet = TRUE)
    attributes <- sf::st_drop_geometry(shapes)
    table <- cbind(attributes, geometry_coordinates(shapes))
    fields_from_table(table, path, sheet = layer)
  })
  do.call(rbind, c(list(new_fields()), fields))
}

is_sqlite <- function(path) {
  magic <- readBin(path, "raw", 16L)
  identical(rawToChar(magic[magic != as.raw(0)]), "SQLite format 3")
}

read_sqlite <- function(path) {
  if (!is_sqlite(path)) {
    rlang::abort("is not an SQLite database", class = "piinata_unsupported")
  }
  need("RSQLite", "SQLite databases")
  need("DBI", "SQLite databases")
  connection <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(connection))
  tables <- DBI::dbListTables(connection)
  fields <- lapply(tables, function(table) {
    fields_from_table(DBI::dbReadTable(connection, table), path, sheet = table)
  })
  do.call(rbind, c(list(new_fields()), fields))
}

read_ods_file <- function(path) {
  need("readODS", "OpenDocument spreadsheets")
  sheets <- readODS::list_ods_sheets(path)
  fields <- lapply(sheets, function(sheet) {
    data <- readODS::read_ods(path, sheet = sheet, col_types = NA, as_tibble = TRUE)
    fields_from_table(data, path, sheet = sheet)
  })
  do.call(rbind, c(list(new_fields()), fields))
}

read_pptx_file <- function(path) {
  need("officer", "PowerPoint files")
  slides <- officer::pptx_summary(officer::read_pptx(path))
  fields <- lapply(split(slides$text, slides$slide_id), function(text) text)
  rows <- lapply(names(fields), function(id) {
    fields_from_text(fields[[id]], path, paste("slide", id))
  })
  do.call(rbind, c(list(new_fields()), rows))
}

more_readers <- function() {
  shapefile_parts <- c("shx", "prj", "cpg", "sbn", "sbx", "qix")
  c(
    list(
      ipynb = read_notebook, geojson = read_geojson, kml = read_kml,
      dbf = read_dbf, shp = read_shapefile, gpkg = read_geopackage,
      sqlite = read_sqlite, sqlite3 = read_sqlite, db = read_sqlite,
      ods = read_ods_file, pptx = read_pptx_file, xlsm = read_excel_file,
      doc = function(path) {
        rlang::abort("is a legacy Word file; save it as docx", class = "piinata_unsupported")
      }
    ),
    stats::setNames(
      rep(list(function(path) ignore_file("part of a shapefile")), length(shapefile_parts)),
      shapefile_parts
    )
  )
}
