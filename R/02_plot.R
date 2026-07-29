# 02_plot.R -- Female unemployment rate, Los Angeles County census tracts
# Data: ACS 2020-2024 5-year estimates, table B23001
# Produces plots/female_unemployment_la.png

suppressMessages({
  library(sf); library(ggplot2); library(dplyr); library(scales)
})

# Run from the project root (or anywhere below it).
root <- if (dir.exists("data")) "." else ".."
stopifnot(dir.exists(file.path(root, "data")))

dat  <- read.csv(file.path(root, "data", "la_female_unemployment_2024.csv"),
                 colClasses = c(GEOID = "character", tract = "character"))
geom <- readRDS(file.path(root, "data", "la_tracts_geom.rds"))

# Suppress tracts with a tiny female civilian labor force -- the rate is not
# meaningful there (25 tracts have none at all: jails, campuses, industrial land).
MIN_CLF <- 50
dat <- dat %>% mutate(rate = ifelse(female_clf >= MIN_CLF, unemp_rate_f, NA_real_))

brk <- c(0, 3, 5, 7.5, 10, 15, Inf)
lab <- c("under 3%", "3 - 5%", "5 - 7.5%", "7.5 - 10%", "10 - 15%", "15% or more")
dat$bin <- cut(dat$rate, breaks = brk, labels = lab, include.lowest = TRUE, right = FALSE)

map <- geom %>% left_join(dat, by = "GEOID")

# Sequential blue ramp, light -> dark (dataviz reference palette, steps 100-650)
ramp <- c("#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#104281")
names(ramp) <- lab

surface <- "#fcfcfb"; ink <- "#0b0b0b"; ink2 <- "#52514e"; grid <- "#e6e5e1"

base_theme <- theme_minimal(base_size = 11) +
  theme(
    plot.background   = element_rect(fill = surface, colour = NA),
    panel.background  = element_rect(fill = surface, colour = NA),
    panel.grid        = element_blank(),
    plot.title        = element_text(face = "bold", size = 15, colour = ink),
    plot.subtitle     = element_text(size = 10, colour = ink2, margin = margin(b = 8)),
    plot.caption      = element_text(size = 8, colour = ink2, hjust = 0),
    legend.title      = element_text(size = 9, colour = ink2),
    legend.text       = element_text(size = 9, colour = ink2),
    axis.text         = element_blank(),
    axis.title        = element_blank()
  )

# --- Panel A: whole county -------------------------------------------------
# Mainland only: the Channel Islands (San Clemente, Santa Catalina) belong to the
# county but sit ~60 miles offshore and would triple the map's height.
pA <- ggplot(map) +
  geom_sf(aes(fill = bin), colour = NA) +
  scale_fill_manual(values = ramp, na.value = "#e6e5e1", drop = FALSE, guide = "none") +
  coord_sf(xlim = c(-118.96, -117.64), ylim = c(33.68, 34.83), expand = FALSE) +
  labs(title = "All of Los Angeles County") +
  base_theme + theme(plot.title = element_text(face = "plain", size = 11, colour = ink2))

# --- Panel B: urbanized basin ---------------------------------------------
pB <- ggplot(map) +
  geom_sf(aes(fill = bin), colour = NA) +
  scale_fill_manual(values = ramp, na.value = "#e6e5e1", drop = FALSE, guide = "none") +
  coord_sf(xlim = c(-118.68, -117.95), ylim = c(33.70, 34.28), expand = FALSE) +
  labs(title = "The urbanized basin, enlarged") +
  base_theme +
  theme(plot.title = element_text(face = "plain", size = 11, colour = ink2),
        panel.border = element_rect(colour = grid, fill = NA, linewidth = 0.4))

# Shared legend, drawn once beside the title rather than inside either map.
legend_grob <- {
  p <- pB + scale_fill_manual(values = ramp, na.value = "#e6e5e1", drop = FALSE, name = NULL,
                              guide = guide_legend(nrow = 1, label.position = "bottom",
                                                   keywidth = unit(26, "pt"), keyheight = unit(7, "pt"))) +
    theme(legend.position = "top", legend.justification = "left")
  g <- ggplotGrob(p)
  g$grobs[[grep("guide-box", g$layout$name)[which(sapply(
    g$grobs[grep("guide-box", g$layout$name)], function(x) !inherits(x, "zeroGrob")))[1]]]]
}

# --- Panel C: distribution -------------------------------------------------
med   <- median(dat$rate, na.rm = TRUE)
XMAX  <- 36
n_off <- sum(dat$rate > XMAX, na.rm = TRUE)
pC <- ggplot(subset(dat, !is.na(rate)), aes(x = rate)) +
  geom_histogram(binwidth = 1, fill = "#3987e5", colour = surface, linewidth = 0.3) +
  geom_vline(xintercept = med, colour = "#e34948", linewidth = 0.6) +
  annotate("text", x = med + 1.2, y = Inf, vjust = 1.6, hjust = 0, size = 3.1, colour = "#e34948",
           label = sprintf("county tract median %.1f%%", med)) +
  annotate("text", x = XMAX, y = Inf, vjust = 1.6, hjust = 1, size = 2.7, colour = ink2,
           label = sprintf("%d tract%s above %d%% not shown", n_off, ifelse(n_off == 1, "", "s"), XMAX)) +
  scale_x_continuous(labels = label_percent(scale = 1), limits = c(0, XMAX),
                     expand = expansion(mult = c(0, 0.02))) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(title = "Distribution across tracts",
       x = "Female unemployment rate", y = "Tracts") +
  theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = surface, colour = NA),
        panel.background = element_rect(fill = surface, colour = NA),
        panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(colour = grid, linewidth = 0.3),
        plot.title = element_text(face = "plain", size = 11, colour = ink2),
        axis.title = element_text(size = 9, colour = ink2),
        axis.text = element_text(size = 9, colour = ink2))

n_shown <- sum(!is.na(dat$rate))
med_cv  <- median(dat$cv_f[is.finite(dat$cv_f) & dat$female_clf >= MIN_CLF], na.rm = TRUE)

cap <- paste0(
  "Source: U.S. Census Bureau, American Community Survey 2020-2024 5-year estimates, table B23001 (sex by age by employment status). ",
  "Rate = women 16 and over unemployed, divided by women 16 and over\n",
  "in the civilian labor force, summed across all age groups. ", n_shown, " of ", nrow(dat),
  " tracts shown; grey tracts have fewer than ", MIN_CLF, " women in the civilian labor force. ",
  "Mainland only -- Santa Catalina and San Clemente\nislands are omitted from the map. ",
  sprintf("These are survey estimates, not a census: the median tract rate here has a coefficient of variation of %.0f%%, so single-tract values are indicative, not precise.", med_cv))

# --- Compose ---------------------------------------------------------------
png(file.path(root, "plots", "female_unemployment_la.png"),
    width = 2600, height = 1850, res = 200, bg = surface)
grid::grid.newpage()
grid::pushViewport(grid::viewport(layout = grid::grid.layout(
  4, 2, heights = grid::unit(c(0.46, 1.15, 0.78, 0.22), "null"),
        widths  = grid::unit(c(1, 1.25), "null"))))
vp <- function(r, c) grid::viewport(layout.pos.row = r, layout.pos.col = c)

grid::pushViewport(vp(1, 1:2))
grid::grid.text("Where women are out of work in Los Angeles County",
                x = 0.010, y = 0.94, just = c("left", "top"),
                gp = grid::gpar(fontsize = 17, fontface = "bold", col = ink))
grid::grid.text(paste0("Unemployment rate among women 16 and over in the civilian labor force, by census tract\n",
                       "American Community Survey 2020-2024 five-year estimates"),
                x = 0.010, y = 0.70, just = c("left", "top"),
                gp = grid::gpar(fontsize = 10.5, col = ink2, lineheight = 1.3))
# Shared legend on its own line, below the subtitle and above both maps.
grid::pushViewport(grid::viewport(x = 0.006, y = 0.02, width = 0.55, height = 0.30,
                                  just = c("left", "bottom")))
grid::grid.draw(legend_grob)
grid::popViewport(2)

print(pA, vp = vp(2:3, 1))
print(pB, vp = vp(2, 2))
print(pC, vp = vp(3, 2))

grid::pushViewport(vp(4, 1:2))
grid::grid.text(cap, x = 0.010, y = 0.78, just = c("left", "top"),
                gp = grid::gpar(fontsize = 7.3, col = ink2, lineheight = 1.35))
invisible(dev.off())

cat("wrote plots/female_unemployment_la.png\n")
cat(sprintf("tracts mapped: %d | median %.2f%% | IQR %.2f-%.2f%%\n", n_shown, med,
            quantile(dat$rate, .25, na.rm = TRUE), quantile(dat$rate, .75, na.rm = TRUE)))
