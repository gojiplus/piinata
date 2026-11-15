# Whole-token vocabulary for field names, labels and question text. A token is
# what remains after splitting on case changes, digits and punctuation, so
# "reason" never matches "son" and "latrine" never matches "lat".
name_terms <- function() {
  list(
    person_name = c(
      "name", "fname", "lname", "firstname", "lastname", "surname", "fullname", "nickname",
      "nombre", "apellido", "nom", "prenom", "naam"
    ),
    phone = c(
      "phone", "mobile", "cell", "cellphone", "telephone", "tel", "whatsapp", "fax",
      "telefono", "celular", "devicephonenum"
    ),
    email = c("email", "mail", "correo", "courriel"),
    address = c(
      "address", "addr", "street", "landmark", "pincode", "zip", "zipcode", "postcode",
      "postal", "direccion", "adresse"
    ),
    date_of_birth = c(
      "dob", "birth", "birthday", "birthdate", "bday", "born", "nacimiento",
      "naissance"
    ),
    location = c("village", "hamlet", "tola", "mohalla", "gaon", "locality", "barangay", "aldea"),
    coordinates = c(
      "gps", "latitude", "longitude", "lat", "lon", "lng", "coordinates", "coord",
      "geopoint", "geolocation"
    ),
    government_id = c(
      "aadhaar", "aadhar", "pan", "passport", "voter", "epic", "ssn", "nid",
      "license", "licence", "cedula", "curp", "dni"
    ),
    online_id = c(
      "ip", "ipaddress", "username", "handle", "twitter", "facebook", "instagram",
      "linkedin"
    ),
    device_id = c("imei", "deviceid", "subscriberid", "simid")
  )
}

# Words that, in a column's name or label, corroborate what its values show:
# the vocabulary above for each kind of finding, and for identity numbers the
# context words of Microsoft Presidio's recognizers. Presidio adds 0.35 to a
# match when such a word comes shortly before it; for a column, the name and
# label are that context.
context_terms <- function() {
  c(
    name_terms(),
    list(
      in_aadhaar = c("aadhaar", "aadhar", "uid", "uidai"), in_pan = "pan",
      in_gstin = c("gst", "gstin"), in_epic = c("epic", "voter"), in_passport = "passport",
      in_mobile = c("mobile", "phone", "cell", "whatsapp"),
      us_ssn = c("ssn", "ssns", "social", "security"), gb_nhs = "nhs",
      iban = c("iban", "bank", "account"),
      intl_payment_card = c("card", "credit", "debit", "visa", "mastercard", "amex", "cc")
    )
  )
}

# Answers to a question about sex or gender. GLiNER tags "Male" and "Female"
# as people, so a column made of these is not sent to it.
gender_words <- function() {
  c(
    "male", "female", "m", "f", "man", "woman", "men", "women", "boy", "girl", "other",
    "non-binary", "nonbinary", "unknown", "hombre", "mujer", "homme", "femme", "purush", "mahila",
    "\u092a\u0941\u0930\u0941\u0937", "\u092e\u0939\u093f\u0932\u093e"
  )
}

# Names of precise decimals that are not places: rates, prices, scores and
# model output. A column so named is never half of a coordinate pair.
not_coordinates <- function() {
  c(
    "rate", "rates", "fx", "exchange", "price", "cost", "amount", "income", "wage", "score",
    "ratio", "pct", "percent", "share", "prob", "probability", "coef", "beta", "estimate",
    "se", "sd", "mean", "variance", "weight", "wt", "height", "length", "width", "index",
    "pvalue", "elasticity"
  )
}

# Fields survey platforms add to every export, matched on the whole name.
platform_terms <- function() {
  c(
    ipaddress = "online_id", recipientlastname = "person_name",
    recipientfirstname = "person_name", recipientemail = "email",
    locationlatitude = "coordinates", locationlongitude = "coordinates",
    externalreference = "online_id", deviceid = "device_id", subscriberid = "device_id",
    simid = "device_id", devicephonenum = "phone", `_submitted_by` = "online_id",
    `_geolocation` = "coordinates", `email address` = "email"
  )
}

# Platform bookkeeping that is unique per response without identifying anyone.
platform_bookkeeping <- function() {
  c(
    "responseid", "startdate", "enddate", "recordeddate", "status", "progress",
    "duration (in seconds)", "finished", "distributionchannel", "userlanguage", "key",
    "instanceid", "_uuid", "_id", "formdef_version", "submissiondate", "starttime", "endtime"
  )
}

# "name" beside one of these names a place or a thing, not a person.
not_a_person <- function() {
  c(
    "village", "gram", "panchayat", "panchyat", "samiti", "block", "district", "state", "ward",
    "tehsil", "taluk", "mandal", "city", "town", "country", "region", "province", "county",
    "school", "college", "hospital", "clinic", "bank", "branch", "company", "firm", "employer",
    "organization", "organisation", "ngo", "party", "scheme", "program", "programme", "project",
    "survey", "file", "variable", "var", "crop", "product", "brand", "item", "form", "unique",
    "flag", "count", "length", "match", "standardized", "std", "constituency", "seat", "gp",
    "dist", "subdistrict", "score", "translate", "code", "id", "type", "category"
  )
}

tokens <- function(x) {
  x <- stringr::str_replace_all(x, "(?<=[a-z])(?=[A-Z])", " ")
  parts <- stringr::str_split(tolower(x), "[^\\p{L}]+")[[1]]
  parts[nzchar(parts)]
}
