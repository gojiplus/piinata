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

tokens <- function(x) {
  x <- stringr::str_replace_all(x, "(?<=[a-z])(?=[A-Z])", " ")
  parts <- stringr::str_split(tolower(x), "[^\\p{L}]+")[[1]]
  parts[nzchar(parts)]
}
