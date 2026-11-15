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
