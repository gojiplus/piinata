# A small survey with known answers. Personal data sit both in plainly named
# columns and behind question numbers; the other columns carry names chosen to
# contain a keyword as a substring.
survey <- function(n = 60) {
  first <- c("Sunita", "Ramesh", "Geeta", "Mohammad", "Lakshmi", "Arjun", "Pooja", "Imran")
  last <- c("Devi", "Yadav", "Meena", "Khan", "Sharma", "Paswan", "Kumari", "Ansari")
  i <- seq_len(n)
  person <- paste(first[i %% 8 + 1], last[(i %/% 8) %% 8 + 1])
  phone <- sprintf("9%09d", 800000000 + i * 7919)
  data.frame(
    resp_name = person,
    hh_phone = paste("+91", substr(phone, 1, 5), substr(phone, 6, 10)),
    dob = sprintf("%02d/%02d/%d", i %% 28 + 1, i %% 12 + 1, 1960 + i %% 40),
    village = c("Palpur", "Netrad", "Biliya")[i %% 3 + 1],
    gps_lat = sprintf("%.6f", 26 + i / 1000),
    q12 = paste0(tolower(first[i %% 8 + 1]), i, "@example.org"),
    q13 = phone,
    q15 = rev(person),
    q20_text = ifelse(i %% 4 == 0, paste("Please call my husband on", phone), "The road is bad"),
    reason_visit = c("work", "family", "health")[i %% 3 + 1],
    season = c("kharif", "rabi")[i %% 2 + 1],
    relation_head = i %% 6,
    latrine_type = i %% 4,
    long_term_plan = i %% 5,
    second_job = i %% 2,
    household_size = i %% 9 + 1,
    personal_income = 2000 + (i %% 30) * 500,
    q30 = c("Yes", "No", "Don't know")[i %% 3 + 1],
    stringsAsFactors = FALSE
  )
}

personal <- c("resp_name", "hh_phone", "dob", "village", "gps_lat", "q12", "q13", "q15", "q20_text")
