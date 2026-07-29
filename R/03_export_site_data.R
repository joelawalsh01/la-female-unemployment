# 03_export_site_data.R -- export the browser payload for the static site
#
# Writes docs/data/tracts.json : one compact JSON file holding both the
# simplified tract outlines and the per-tract attributes.
#
# Geometry is simplified in a projected CRS (California Albers, metres) rather
# than in lon/lat -- sf refuses to drop topology preservation on ellipsoidal
# coordinates, so simplifying in degrees barely removes any vertices at all.
# 40 m tolerance takes the county from ~294k vertices to ~30k with no visible
# change at the zoom levels the site offers.

suppressMessages({ library(sf); library(jsonlite) })

root <- if (dir.exists("data")) "." else ".."
TOL  <- 40      # metres
DP   <- 4       # decimal places kept in lon/lat (~11 m)

dat <- read.csv(file.path(root, "data", "la_female_unemployment_2024.csv"),
                colClasses = c(GEOID = "character", tract = "character"))
g   <- readRDS(file.path(root, "data", "la_tracts_geom.rds"))
g   <- g[!grepl("^0603759", g$GEOID), ]          # drop the offshore Channel Islands

s <- st_transform(st_simplify(st_transform(g, 3310), dTolerance = TOL,
                              preserveTopology = TRUE), 4326)
stopifnot(!any(st_is_empty(s)))

# Each tract becomes a list of rings; each ring is a flat [x0,y0,x1,y1,...].
# Interior rings (holes) are kept -- a handful of LA tracts enclose others.
rings_of <- function(geom) {
  polys <- if (inherits(geom, "MULTIPOLYGON")) geom else list(geom)
  out <- list()
  for (p in polys) for (r in p) {
    xy <- round(as.matrix(r)[, 1:2, drop = FALSE], DP)
    if (nrow(xy) >= 4) out[[length(out) + 1L]] <- as.vector(t(xy))
  }
  out
}

geo <- lapply(st_geometry(s), rings_of)
names(geo) <- s$GEOID

keep <- c("GEOID", "tract", "unemp_rate_f", "unemp_rate_f_moe", "unemp_rate_m",
          "gap_f_minus_m", "cv_f", "female_clf", "female_unemp", "male_clf",
          "median_hh_income", "pct_poverty", "pct_bachelors_plus",
          "pct_hispanic", "pct_white_nh", "pct_black_nh", "pct_asian_nh", "total_pop")
d <- dat[match(s$GEOID, dat$GEOID), keep]

rnd <- function(x, k) ifelse(is.na(x), NA, round(x, k))
for (v in c("unemp_rate_f", "unemp_rate_f_moe", "unemp_rate_m", "gap_f_minus_m",
            "pct_poverty", "pct_bachelors_plus", "pct_hispanic", "pct_white_nh",
            "pct_black_nh", "pct_asian_nh")) d[[v]] <- rnd(d[[v]], 2)
d$cv_f <- rnd(d$cv_f, 1)   # 1 dp: rounding to whole numbers shifts band boundaries

payload <- list(
  meta = list(
    source  = "U.S. Census Bureau, ACS 2020-2024 5-year estimates, tables B23001, B19013, B03002, B17001, B15003",
    vintage = "2020-2024 ACS 5-year",
    county  = "Los Angeles County, California",
    ntracts = nrow(d),
    note    = "Channel Islands tracts omitted from the map geometry.",
    bbox    = as.numeric(round(st_bbox(s), 4))
  ),
  ids    = d$GEOID,
  fields = setdiff(keep, "GEOID"),
  rows   = lapply(seq_len(nrow(d)), function(i) unname(as.list(d[i, setdiff(keep, "GEOID")]))),
  shapes = unname(lapply(s$GEOID, function(id) geo[[id]]))
)

dir.create(file.path(root, "docs", "data"), recursive = TRUE, showWarnings = FALSE)
p <- file.path(root, "docs", "data", "tracts.json")
write(toJSON(payload, digits = NA, na = "null", auto_unbox = TRUE), p)

nv <- sum(sapply(geo, function(rs) sum(sapply(rs, length)))) / 2
cat(sprintf("wrote %s | %d tracts | %.0f vertices | %.2f MB\n",
            p, nrow(d), nv, file.size(p) / 1e6))
