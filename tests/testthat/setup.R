if (is.na(Sys.getenv("NOT_CRAN", unset = NA))) {
  Sys.setenv(NOT_CRAN = "true")
}
