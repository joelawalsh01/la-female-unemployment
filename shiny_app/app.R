# app.R -- Los Angeles County female unemployment explorer
#
# Browser-based Shiny app over the ACS 2020-2024 5-year tract file built by
# R/01_build_data.R. Run from the project root with:
#     shiny::runApp("shiny_app")
#
# Deliberately depends only on shiny + bslib + ggplot2 + sf + DT + dplyr +
# scales, so it runs without leaflet/plotly (which need a system GDAL build).
# The map is a ggplot/sf choropleth wired to click and brush events, which
# gives click-to-identify and drag-to-select without a JS mapping library.

library(shiny); library(bslib); library(ggplot2); library(dplyr)
library(sf); library(DT); library(scales)

# ---------------------------------------------------------------- data ------
root <- if (dir.exists("data")) "." else ".."
dat  <- read.csv(file.path(root, "data", "la_female_unemployment_2024.csv"),
                 colClasses = c(GEOID = "character", tract = "character"))
geom <- readRDS(file.path(root, "data", "la_tracts_geom.rds"))
geom <- geom[!grepl("^0603759", geom$GEOID), ]        # drop the Channel Islands
shapes <- geom %>% select(GEOID, NAMELSAD)

MEASURES <- c(
  "Female unemployment rate"          = "unemp_rate_f",
  "Male unemployment rate"            = "unemp_rate_m",
  "Female minus male (pct. points)"   = "gap_f_minus_m"
)
CORRELATES <- c(
  "Median household income ($)"       = "median_hh_income",
  "Share in poverty (%)"              = "pct_poverty",
  "Share with a bachelor's or more (%)" = "pct_bachelors_plus",
  "Share Hispanic or Latino (%)"      = "pct_hispanic",
  "Share Black, non-Hispanic (%)"     = "pct_black_nh",
  "Share White, non-Hispanic (%)"     = "pct_white_nh",
  "Share Asian, non-Hispanic (%)"     = "pct_asian_nh",
  "Women in the civilian labor force" = "female_clf",
  "Total population"                  = "total_pop"
)
lab_of <- function(v, tbl) names(tbl)[match(v, tbl)]

RAMP <- c("#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#104281")
DIV  <- c("#104281", "#3987e5", "#9ec5f4", "#f0efec", "#f0a3a2", "#e34948", "#a52220")
SURF <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"; GRID <- "#e6e5e1"

thm <- theme_minimal(base_size = 12) +
  theme(plot.background = element_rect(fill = SURF, colour = NA),
        panel.background = element_rect(fill = SURF, colour = NA),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
        plot.title = element_text(face = "bold", size = 13, colour = INK),
        plot.subtitle = element_text(size = 10, colour = INK2),
        axis.title = element_text(size = 10, colour = INK2),
        axis.text = element_text(colour = INK2),
        legend.title = element_text(size = 10, colour = INK2),
        legend.text = element_text(size = 9, colour = INK2))
map_thm <- thm + theme(panel.grid = element_blank(), axis.text = element_blank(),
                       axis.title = element_blank())

fmt <- function(x, d = 2) ifelse(is.na(x), "--", formatC(x, format = "f", digits = d, big.mark = ","))

# ------------------------------------------------------------------ ui ------
ui <- page_sidebar(
  title = "Women's unemployment across Los Angeles County census tracts",
  theme = bs_theme(version = 5, bg = "#ffffff", fg = "#0b0b0b", primary = "#256abf"),

  sidebar = sidebar(
    width = 330,
    selectInput("measure", "Measure", choices = MEASURES, selected = "unemp_rate_f"),
    hr(),
    h6("Restrict the sample", style = "color:#52514e;margin-bottom:.4rem"),
    sliderInput("min_clf", "Minimum women in the civilian labor force",
                min = 0, max = 500, value = 50, step = 25),
    sliderInput("max_cv", "Maximum coefficient of variation (%)",
                min = 10, max = 200, value = 200, step = 10),
    helpText(HTML("ACS tract estimates are noisy. A CV above 30-40% is conventionally ",
                  "treated as unreliable; the median tract here sits near 55%. ",
                  "Tighten this slider to keep only well-measured tracts.")),
    hr(),
    selectInput("corr", "Compare against", choices = CORRELATES, selected = "pct_poverty"),
    checkboxInput("weighted", "Weight statistics by female labor force", TRUE),
    hr(),
    downloadButton("dl", "Download filtered data (CSV)", class = "btn-sm")
  ),

  layout_columns(
    fill = FALSE, col_widths = c(3, 3, 3, 3),
    value_box("Tracts in view",   textOutput("vb_n"),      theme = "primary"),
    value_box("Median",           textOutput("vb_med"),    theme = "secondary"),
    value_box("Labor-force weighted mean", textOutput("vb_wm"), theme = "secondary"),
    value_box("Interquartile range",      textOutput("vb_iqr"), theme = "secondary")
  ),

  navset_card_tab(
    nav_panel("Map",
      card_body(
        p(class = "text-muted small",
          "Click a tract to read its estimate and margin of error. Drag a box to summarise a neighbourhood."),
        plotOutput("map", height = "640px", click = "map_click", brush = brushOpts("map_brush", resetOnNew = TRUE)),
        uiOutput("clicked")
      )),
    nav_panel("Distribution",
      card_body(
        layout_columns(col_widths = c(6, 6),
          plotOutput("hist", height = "420px"),
          plotOutput("ecdf", height = "420px")),
        plotOutput("box_group", height = "300px")
      )),
    nav_panel("Relationships",
      card_body(
        plotOutput("scatter", height = "520px", brush = brushOpts("sc_brush", resetOnNew = TRUE)),
        uiOutput("fitinfo")
      )),
    nav_panel("Descriptive statistics",
      card_body(
        h5("Summary of the selected measure"), tableOutput("desc"),
        h5("Correlations with the selected measure"),
        p(class = "text-muted small", "Pearson and Spearman coefficients over the tracts currently in view."),
        tableOutput("cors"),
        h5("Reliability of the estimates"), tableOutput("rel")
      )),
    nav_panel("Data",
      card_body(DTOutput("tbl"))),
    nav_panel("Notes",
      card_body(includeMarkdown(file.path(root, "shiny_app", "notes.md"))))
  )
)

# --------------------------------------------------------------- server -----
server <- function(input, output, session) {

  filtered <- reactive({
    d <- dat
    d$value <- d[[input$measure]]
    d <- d[!is.na(d$value) & d$female_clf >= input$min_clf, ]
    if (input$max_cv < 200) d <- d[is.finite(d$cv_f) & d$cv_f <= input$max_cv, ]
    d
  })

  wmean <- function(x, w) sum(x * w, na.rm = TRUE) / sum(w[!is.na(x)], na.rm = TRUE)
  stat_w <- reactive(if (isTRUE(input$weighted)) filtered()$female_clf else rep(1, nrow(filtered())))

  output$vb_n   <- renderText(format(nrow(filtered()), big.mark = ","))
  output$vb_med <- renderText(paste0(fmt(median(filtered()$value, na.rm = TRUE), 1), "%"))
  output$vb_wm  <- renderText(paste0(fmt(wmean(filtered()$value, filtered()$female_clf), 1), "%"))
  output$vb_iqr <- renderText({
    q <- quantile(filtered()$value, c(.25, .75), na.rm = TRUE)
    paste0(fmt(q[1], 1), "% to ", fmt(q[2], 1), "%")
  })

  # ------------------------------------------------------------- map --------
  map_df <- reactive(left_join(shapes, filtered()[, c("GEOID", "value")], by = "GEOID"))

  output$map <- renderPlot({
    d <- map_df(); div <- input$measure == "gap_f_minus_m"
    g <- ggplot(d) + geom_sf(aes(fill = value), colour = NA) +
      coord_sf(expand = FALSE) + map_thm +
      labs(title = lab_of(input$measure, MEASURES),
           subtitle = paste(format(nrow(filtered()), big.mark = ","),
                            "tracts shown; grey tracts are filtered out or unmeasured"))
    if (div) {
      lim <- max(abs(quantile(d$value, c(.02, .98), na.rm = TRUE)))
      g + scale_fill_gradientn(colours = DIV, limits = c(-lim, lim), oob = squish,
                               na.value = GRID, name = "pct. points")
    } else {
      g + scale_fill_gradientn(colours = RAMP,
                               limits = quantile(d$value, c(.02, .98), na.rm = TRUE),
                               oob = squish, na.value = GRID, name = "%")
    }
  }, res = 108)

  hit <- reactiveVal(NULL)
  observeEvent(input$map_click, {
    p  <- st_sfc(st_point(c(input$map_click$x, input$map_click$y)), crs = st_crs(shapes))
    ix <- st_intersects(p, shapes)[[1]]
    hit(if (length(ix)) shapes$GEOID[ix[1]] else NULL)
  })

  output$clicked <- renderUI({
    req(hit()); r <- dat[dat$GEOID == hit(), ]; if (!nrow(r)) return(NULL)
    ci <- sprintf("%s%% (90%% CI %s to %s)", fmt(r$unemp_rate_f, 1),
                  fmt(pmax(0, r$unemp_rate_f - r$unemp_rate_f_moe), 1),
                  fmt(r$unemp_rate_f + r$unemp_rate_f_moe, 1))
    card(class = "mt-2", card_header(paste("Census tract", r$tract, "-", r$GEOID)),
      card_body(layout_columns(col_widths = c(4, 4, 4),
        div(strong("Female unemployment"), br(), ci),
        div(strong("Male unemployment"), br(), paste0(fmt(r$unemp_rate_m, 1), "%")),
        div(strong("Women in civilian labor force"), br(), format(r$female_clf, big.mark = ",")),
        div(strong("Median household income"), br(),
            ifelse(is.na(r$median_hh_income), "not published", dollar(r$median_hh_income))),
        div(strong("Share in poverty"), br(), paste0(fmt(r$pct_poverty, 1), "%")),
        div(strong("Coefficient of variation"), br(),
            paste0(fmt(r$cv_f, 0), "%",
                   if (isTRUE(r$cv_f > 40)) " - treat this tract's rate with caution" else ""))
      )))
  })

  output$box_group <- renderPlot({
    d <- filtered()
    b <- cut(d$median_hh_income, quantile(dat$median_hh_income, seq(0, 1, .2), na.rm = TRUE),
             labels = c("poorest fifth", "2nd", "3rd", "4th", "richest fifth"),
             include.lowest = TRUE)
    d <- d[!is.na(b), ]; d$band <- b[!is.na(b)]
    ggplot(d, aes(band, value)) +
      geom_boxplot(fill = "#9ec5f4", colour = "#256abf", outlier.size = 0.6,
                   outlier.colour = "#52514e", width = 0.6) +
      labs(title = paste(lab_of(input$measure, MEASURES), "by tract income band"),
           subtitle = "Tracts grouped into fifths of county median household income",
           x = NULL, y = lab_of(input$measure, MEASURES)) + thm
  }, res = 108)

  # ----------------------------------------------------- distribution ------
  output$hist <- renderPlot({
    d <- filtered(); m <- median(d$value, na.rm = TRUE)
    ggplot(d, aes(value)) +
      geom_histogram(bins = 40, fill = "#3987e5", colour = SURF, linewidth = 0.3) +
      geom_vline(xintercept = m, colour = "#e34948", linewidth = 0.6) +
      annotate("text", x = m, y = Inf, vjust = 1.8, hjust = -0.08, size = 3.4,
               colour = "#e34948", label = paste0("median ", fmt(m, 1), "%")) +
      labs(title = "Distribution across tracts", x = lab_of(input$measure, MEASURES), y = "Tracts") + thm
  }, res = 108)

  output$ecdf <- renderPlot({
    ggplot(filtered(), aes(value)) +
      stat_ecdf(geom = "step", colour = "#256abf", linewidth = 0.9) +
      scale_y_continuous(labels = percent) +
      labs(title = "Cumulative share of tracts", x = lab_of(input$measure, MEASURES),
           y = "Share of tracts at or below") + thm
  }, res = 108)

  # ------------------------------------------------------ relationships ----
  output$scatter <- renderPlot({
    d <- filtered(); d$x <- d[[input$corr]]; d <- d[!is.na(d$x), ]
    ggplot(d, aes(x, value)) +
      geom_point(aes(size = female_clf), alpha = 0.35, colour = "#256abf", stroke = 0) +
      geom_smooth(aes(weight = if (isTRUE(input$weighted)) female_clf else NULL),
                  method = "lm", formula = y ~ x, colour = "#e34948", fill = "#f0a3a2", linewidth = 0.8) +
      scale_size_area(max_size = 6, guide = "none") +
      labs(title = paste(lab_of(input$measure, MEASURES), "vs", lab_of(input$corr, CORRELATES)),
           subtitle = paste("Each point is a census tract, sized by female civilian labor force.",
                            if (isTRUE(input$weighted)) "Fit is labor-force weighted." else "Fit is unweighted."),
           x = lab_of(input$corr, CORRELATES), y = lab_of(input$measure, MEASURES)) + thm
  }, res = 108)

  output$fitinfo <- renderUI({
    d <- filtered(); d$x <- d[[input$corr]]; d <- d[!is.na(d$x) & !is.na(d$value), ]
    if (nrow(d) < 10) return(p("Too few tracts to fit."))
    w <- if (isTRUE(input$weighted)) d$female_clf else rep(1, nrow(d))
    m <- lm(value ~ x, data = d, weights = w); s <- summary(m)
    br <- brushedPoints(d, input$sc_brush, xvar = "x", yvar = "value")
    tagList(
      p(sprintf("Slope %.4f (SE %.4f), p = %.3g. R-squared %.3f over %d tracts. Pearson r = %.3f, Spearman rho = %.3f.",
                coef(s)[2, 1], coef(s)[2, 2], coef(s)[2, 4], s$r.squared, nrow(d),
                cor(d$x, d$value, use = "complete.obs"),
                cor(d$x, d$value, method = "spearman", use = "complete.obs"))),
      if (nrow(br)) p(class = "text-muted",
        sprintf("Brushed selection: %d tracts, median %s = %.1f%%, median %s = %s.",
                nrow(br), lab_of(input$measure, MEASURES), median(br$value, na.rm = TRUE),
                lab_of(input$corr, CORRELATES), fmt(median(br$x, na.rm = TRUE), 1)))
    )
  })

  # ------------------------------------------------ descriptive statistics --
  output$desc <- renderTable({
    v <- filtered()$value; w <- stat_w()
    q <- quantile(v, c(.05, .10, .25, .50, .75, .90, .95), na.rm = TRUE)
    data.frame(
      Statistic = c("Tracts", "Mean", if (isTRUE(input$weighted)) "Weighted mean" else "Weighted mean (off)",
                    "Standard deviation", "Minimum", "5th pct", "10th pct", "25th pct", "Median",
                    "75th pct", "90th pct", "95th pct", "Maximum", "Interquartile range", "Skewness"),
      Value = c(format(length(v), big.mark = ","), fmt(mean(v, na.rm = TRUE)),
                fmt(wmean(v, w)), fmt(sd(v, na.rm = TRUE)), fmt(min(v, na.rm = TRUE)),
                fmt(q[1]), fmt(q[2]), fmt(q[3]), fmt(q[4]), fmt(q[5]), fmt(q[6]), fmt(q[7]),
                fmt(max(v, na.rm = TRUE)), fmt(q[5] - q[3]),
                fmt(mean((v - mean(v, na.rm = TRUE))^3, na.rm = TRUE) / sd(v, na.rm = TRUE)^3)),
      check.names = FALSE)
  }, striped = TRUE, width = "460px")

  output$cors <- renderTable({
    d <- filtered()
    do.call(rbind, lapply(names(CORRELATES), function(nm) {
      x <- d[[CORRELATES[[nm]]]]; ok <- !is.na(x) & !is.na(d$value)
      if (sum(ok) < 10) return(NULL)
      data.frame(Correlate = nm, `Pearson r` = round(cor(x[ok], d$value[ok]), 3),
                 `Spearman rho` = round(cor(x[ok], d$value[ok], method = "spearman"), 3),
                 Tracts = sum(ok), check.names = FALSE)
    }))
  }, striped = TRUE, width = "620px")

  output$rel <- renderTable({
    d <- filtered(); cv <- d$cv_f[is.finite(d$cv_f)]
    data.frame(
      Measure = c("Median CV of the female rate", "Tracts with CV at or below 15% (reliable)",
                  "CV 15-30% (usable)", "CV 30-40% (weak)", "CV above 40% (unreliable)",
                  "Median 90% margin of error (pct. points)"),
      Value = c(paste0(fmt(median(cv), 0), "%"),
                sprintf("%d (%.0f%%)", sum(cv <= 15), 100 * mean(cv <= 15)),
                sprintf("%d (%.0f%%)", sum(cv > 15 & cv <= 30), 100 * mean(cv > 15 & cv <= 30)),
                sprintf("%d (%.0f%%)", sum(cv > 30 & cv <= 40), 100 * mean(cv > 30 & cv <= 40)),
                sprintf("%d (%.0f%%)", sum(cv > 40), 100 * mean(cv > 40)),
                fmt(median(d$unemp_rate_f_moe, na.rm = TRUE), 1)),
      check.names = FALSE)
  }, striped = TRUE, width = "560px")

  # ------------------------------------------------------------ data -------
  output$tbl <- renderDT({
    d <- filtered() %>%
      transmute(GEOID, Tract = tract,
                `Female rate %` = round(unemp_rate_f, 1), `+/- MOE` = round(unemp_rate_f_moe, 1),
                `CV %` = round(cv_f, 0), `Male rate %` = round(unemp_rate_m, 1),
                `Gap (F-M)` = round(gap_f_minus_m, 1), `Female CLF` = female_clf,
                `Median income` = median_hh_income, `Poverty %` = round(pct_poverty, 1),
                `BA+ %` = round(pct_bachelors_plus, 1), `Hispanic %` = round(pct_hispanic, 1))
    datatable(d, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 25, dom = "Bfrtip", buttons = c("copy", "csv"),
                             scrollX = TRUE))
  })

  output$dl <- downloadHandler(
    filename = function() sprintf("la_%s_filtered.csv", input$measure),
    content  = function(f) write.csv(filtered(), f, row.names = FALSE)
  )
}

shinyApp(ui, server)
