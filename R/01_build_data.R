# 01_build_data.R -- Build the Los Angeles County tract analysis file
#
# Source: U.S. Census Bureau, American Community Survey 2020-2024 5-year
# estimates, distributed as the public "table-based summary file". No API key
# is required for these files (the api.census.gov data endpoints now do).
#
# Writes: data/la_female_unemployment_2024.csv
#         data/la_tracts_geom.rds
#
# Outcome measure
#   Female unemployment rate = (women 16+ unemployed) / (women 16+ in the
#   civilian labor force), summed over every age group in table B23001.
#   Note this is a *civilian* labor-force denominator, which is the standard
#   unemployment-rate definition; women in the Armed Forces are excluded from
#   both numerator and denominator.

suppressMessages({ library(data.table); library(sf) })

YEAR   <- 2024
STATE  <- "06"; COUNTY <- "037"          # California / Los Angeles County
PREFIX <- sprintf("1400000US%s%s", STATE, COUNTY)
SF_URL <- sprintf("https://www2.census.gov/programs-surveys/acs/summary_file/%d/table-based-SF/data/5YRData", YEAR)
TIGER  <- sprintf("https://www2.census.gov/geo/tiger/TIGER%d/TRACT/tl_%d_%s_tract.zip", YEAR, YEAR, STATE)

root <- if (dir.exists("data")) "." else ".."
raw  <- file.path(root, "data", "raw"); dir.create(raw, showWarnings = FALSE, recursive = TRUE)

# --- helper: download one table, keep only LA County tracts, delete the rest --
# The national files are 80-300 MB each; we never keep them on disk.
get_table <- function(tbl) {
  keep <- file.path(raw, sprintf("%s_la.csv", tbl))
  if (file.exists(keep)) return(fread(keep, colClasses = list(character = "GEO_ID")))
  tmp <- tempfile(fileext = ".dat")
  url <- sprintf("%s/acsdt5y%d-%s.dat", SF_URL, YEAR, tolower(tbl))
  message("downloading ", tbl, " ...")
  utils::download.file(url, tmp, quiet = TRUE, mode = "wb")
  hdr <- strsplit(readLines(tmp, n = 1), "|", fixed = TRUE)[[1]]
  lin <- grep(PREFIX, readLines(tmp), value = TRUE, fixed = TRUE)
  unlink(tmp)
  dt <- fread(text = paste(lin, collapse = "\n"), sep = "|", header = FALSE,
              col.names = hdr, colClasses = list(character = 1))
  fwrite(dt, keep)
  dt[]
}

# --- B23001: sex by age by employment status ---------------------------------
b23 <- get_table("B23001")

# Line numbers within B23001. Ages 16-64 split labour force into Armed Forces vs
# Civilian, so the civilian labour force is read off the "Civilian:" line. Ages
# 65+ have no Armed Forces line, so "In labor force:" *is* the civilian total.
F_CIV  <- c(92, 99, 106, 113, 120, 127, 134, 141, 148, 155); F_LF65 <- c(160, 165, 170)
F_UNE  <- c(94, 101, 108, 115, 122, 129, 136, 143, 150, 157, 162, 167, 172)
M_CIV  <- c(6, 13, 20, 27, 34, 41, 48, 55, 62, 69);          M_LF65 <- c(74, 79, 84)
M_UNE  <- c(8, 15, 22, 29, 36, 43, 50, 57, 64, 71, 76, 81, 86)

vE <- function(n) sprintf("B23001_E%03d", n)
vM <- function(n) sprintf("B23001_M%03d", n)

# Census publishes -666666666 and friends as "not available" sentinels.
clean <- function(x) { x <- as.numeric(x); x[x <= -666666666] <- NA_real_; x }

sum_est <- function(dt, n) rowSums(sapply(vE(n), function(v) clean(dt[[v]])))

# ACS aggregation rule (General Handbook ch. 8): MOE of a sum is the root sum of
# squares of the component MOEs, counting *only one* zero-estimate cell -- the
# largest -- so that runs of empty age cells do not inflate the result.
agg_moe <- function(dt, n) {
  est <- sapply(vE(n), function(v) clean(dt[[v]]))
  moe <- abs(sapply(vM(n), function(v) clean(dt[[v]])))
  nz  <- ifelse(est == 0, 0, moe); zr <- ifelse(est == 0, moe, 0)
  nz[is.na(nz)] <- 0; zr[is.na(zr)] <- 0
  sqrt(rowSums(nz^2) + apply(zr, 1, max)^2)
}

# MOE of a proportion (handbook ch. 8). When the radicand goes negative the
# numerator is not a subset of the denominator in the sampling sense; the
# handbook says fall back to the ratio formula (a + instead of a -).
prop_moe <- function(N, Nm, D, Dm) {
  p <- N / D; inner <- Nm^2 - (p^2) * (Dm^2)
  bad <- which(inner < 0)                       # which() drops NA/NaN safely
  inner[bad] <- (Nm^2 + (p^2) * (Dm^2))[bad]
  out <- 100 * sqrt(inner) / D
  out[!is.finite(out)] <- NA_real_              # tracts with an empty labour force
  out
}

dat <- data.table(GEOID = sub("^1400000US", "", b23$GEO_ID))
dat[, `:=`(
  female_clf  = sum_est(b23, c(F_CIV, F_LF65)), female_unemp = sum_est(b23, F_UNE),
  male_clf    = sum_est(b23, c(M_CIV, M_LF65)), male_unemp   = sum_est(b23, M_UNE)
)]
Fdm <- agg_moe(b23, c(F_CIV, F_LF65)); Fnm <- agg_moe(b23, F_UNE)
Mdm <- agg_moe(b23, c(M_CIV, M_LF65)); Mnm <- agg_moe(b23, M_UNE)

dat[, `:=`(
  unemp_rate_f     = 100 * female_unemp / female_clf,
  unemp_rate_f_moe = prop_moe(female_unemp, Fnm, female_clf, Fdm),
  unemp_rate_m     = 100 * male_unemp   / male_clf,
  unemp_rate_m_moe = prop_moe(male_unemp,   Mnm, male_clf,   Mdm)
)]
for (v in c("unemp_rate_f", "unemp_rate_m"))       # empty labour force -> NA, not NaN
  set(dat, which(!is.finite(dat[[v]])), v, NA_real_)
dat[, gap_f_minus_m := unemp_rate_f - unemp_rate_m]

# Coefficient of variation of the female rate: MOE is at 90% confidence, so the
# standard error is MOE / 1.645. Census guidance treats CV > 30-40% as unreliable.
# Where the estimated rate is exactly 0 the CV is undefined (not zero, and not
# infinite in any useful sense) -- 70 LA tracts are in that position. Leave it
# missing rather than letting Inf leak into the reliability tables.
dat[, cv_f := (unemp_rate_f_moe / 1.645) / unemp_rate_f * 100]
set(dat, which(!is.finite(dat$cv_f)), "cv_f", NA_real_)

# --- Correlates --------------------------------------------------------------
b19 <- get_table("B19013"); b03 <- get_table("B03002")
b17 <- get_table("B17001"); b15 <- get_table("B15003")
key <- function(dt) sub("^1400000US", "", dt$GEO_ID)

dat[data.table(GEOID = key(b19), median_hh_income = clean(b19$B19013_E001)),
    median_hh_income := i.median_hh_income, on = "GEOID"]

pov <- data.table(GEOID = key(b17),
                  pct_poverty = 100 * clean(b17$B17001_E002) / clean(b17$B17001_E001))
dat[pov, pct_poverty := i.pct_poverty, on = "GEOID"]

ed25 <- clean(b15$B15003_E001)
bap  <- rowSums(sapply(sprintf("B15003_E%03d", 22:25), function(v) clean(b15[[v]])))
dat[data.table(GEOID = key(b15), pct_bachelors_plus = 100 * bap / ed25),
    pct_bachelors_plus := i.pct_bachelors_plus, on = "GEOID"]

tp <- clean(b03$B03002_E001)
race <- data.table(GEOID = key(b03), total_pop = tp,
                   pct_hispanic = 100 * clean(b03$B03002_E012) / tp,
                   pct_white_nh = 100 * clean(b03$B03002_E003) / tp,
                   pct_black_nh = 100 * clean(b03$B03002_E004) / tp,
                   pct_asian_nh = 100 * clean(b03$B03002_E006) / tp)
dat[race, `:=`(total_pop = i.total_pop, pct_hispanic = i.pct_hispanic,
               pct_white_nh = i.pct_white_nh, pct_black_nh = i.pct_black_nh,
               pct_asian_nh = i.pct_asian_nh), on = "GEOID"]

dat[, tract := substr(GEOID, 6, 11)]
setcolorder(dat, c("GEOID", "tract"))
setorder(dat, GEOID)
fwrite(dat, file.path(root, "data", "la_female_unemployment_2024.csv"))

# --- Geometry ----------------------------------------------------------------
gpath <- file.path(root, "data", "la_tracts_geom.rds")
if (!file.exists(gpath)) {
  z <- tempfile(fileext = ".zip"); d <- tempfile(); dir.create(d)
  message("downloading TIGER tract geometry ...")
  utils::download.file(TIGER, z, quiet = TRUE, mode = "wb"); utils::unzip(z, exdir = d)
  g <- st_read(list.files(d, "\\.shp$", full.names = TRUE), quiet = TRUE)
  g <- g[g$COUNTYFP == COUNTY, c("GEOID", "NAMELSAD", "ALAND", "AWATER")]
  g <- st_simplify(st_transform(g, 4269), dTolerance = 2e-4, preserveTopology = TRUE)
  saveRDS(g, gpath); unlink(c(z, d), recursive = TRUE)
}

cat(sprintf("tracts: %d | female rate median %.2f%% | median CV %.0f%%\n",
            nrow(dat), median(dat$unemp_rate_f, na.rm = TRUE),
            median(dat$cv_f[is.finite(dat$cv_f)], na.rm = TRUE)))
