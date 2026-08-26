# Women's unemployment across Los Angeles County census tracts

**→ Live site: https://joelawalsh01.github.io/la-female-unemployment/**

Tract-level female unemployment for all 2,498 census tracts in Los Angeles
County, from the **American Community Survey 2020–2024 five-year estimates** —
the most recent ACS release carrying tract-level detail (published December
2025). Includes a static figure, a browser-based Shiny explorer, a dependency-free
static site, and a SAS reproduction of the whole pipeline.

```
data/la_female_unemployment_2024.csv   2,498 tracts x 20 columns (the analysis file)
data/la_tracts_geom.rds                TIGER/Line 2024 tract geometry, simplified
data/raw/*.csv                         LA-County slices of the five ACS source tables
R/01_build_data.R                      download -> compute -> write the analysis file
R/02_plot.R                            the figure
R/03_export_site_data.R                export the browser payload for the static site
plots/female_unemployment_la.png       the figure
shiny_app/app.R                        the interactive explorer (needs a running R)
shiny_app/notes.md                     methodology notes shown inside the app
docs/index.html                        the static site served by GitHub Pages
docs/data/tracts.json                  ~830 KB: simplified outlines + attributes
sas/la_female_unemployment.sas         the same analysis in SAS
report/data_sources.pdf                data sources & provenance report (LaTeX in data_sources.tex)
```

## The live site vs the Shiny app

They cover the same ground by different means. GitHub Pages serves static files
only — it cannot run an R process — so `docs/index.html` is a self-contained
page (no frameworks, no CDN) that reads one JSON payload and draws the
choropleth to a canvas with an off-screen colour-index buffer for hit-testing.
It gives the same filters, click-to-identify, distribution, scatter and stats
tables as the Shiny app, and loads in about a second.

The Shiny app remains the better tool for anything beyond that: it holds the
full data frame, so you can add measures, brush the scatter, and export filtered
subsets. Run it locally with the command below.

## Running it

```bash
Rscript R/01_build_data.R          # ~1 min; re-downloads only what is missing
Rscript R/02_plot.R                # writes plots/female_unemployment_la.png
Rscript R/03_export_site_data.R    # writes docs/data/tracts.json
Rscript -e 'shiny::runApp("shiny_app", port = 7788)'

cd docs && python3 -m http.server  # preview the static site locally
```

The app needs `shiny`, `bslib`, `ggplot2`, `dplyr`, `sf`, `DT`, `scales`,
`data.table` — all already installed here. It deliberately avoids `leaflet` and
`plotly`, which failed to compile on this machine (they need a system GDAL/PROJ
build). The map is a `ggplot`/`sf` choropleth wired to Shiny click and brush
events, so you still get click-to-identify a tract and drag-to-summarise a
neighbourhood.

## How the measure is built

**Female unemployment rate** = women aged 16+ who are unemployed ÷ women aged
16+ in the *civilian* labor force, summed across every age band of ACS table
**B23001** (sex by age by employment status).

Two things worth knowing about that choice:

- The obvious shortcut, subject table **S2301**, publishes a ready-made female
  unemployment rate — but only for ages 20–64 (`S2301_C04_023E`). Building from
  B23001 covers the full 16-and-over population and lets the margins of error be
  aggregated properly.
- Ages 16–64 in B23001 split the labor force into Armed Forces vs Civilian, so
  the denominator comes off the `Civilian:` line. Ages 65+ have no Armed Forces
  line, so there `In labor force:` *is* the civilian total. Getting this wrong
  silently drops everyone over 65.

Margins of error are aggregated by the rules in [ACS General Handbook ch. 8](https://www.census.gov/content/dam/Census/library/publications/2018/acs/acs_general_handbook_2018_ch08.pdf):
root-sum-of-squares for sums, counting only the largest zero-estimate cell; the
proportion formula for the rate, falling back to the ratio formula when the
radicand goes negative.

**Data source note.** `api.census.gov` data endpoints now require a free API
key. This pipeline instead reads the public [table-based summary files](https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/),
which are static downloads and need no key. The build script pulls each national
file (80–305 MB), keeps the LA County rows, and deletes the rest — the SAS script
does the same, and includes a keyed API alternative in a trailing comment.

## What the data show

| | |
|---|---|
| County-wide female unemployment rate | **7.2%** |
| County-wide male rate | 7.3% |
| Median across tracts | 6.2% |
| Interquartile range across tracts | 3.5% – 10.1% |
| Range across tracts | 0% – 43% |

**In aggregate there is essentially no gender gap** — 7.2% vs 7.3% county-wide,
and the median tract-level gap is −0.1 points. The interesting variation is
geographic, not between the sexes.

**The spread across neighbourhoods is large and follows income closely.** Median
female unemployment by fifth of tract median household income:

| Income fifth | Poorest | 2nd | 3rd | 4th | Richest |
|---|---|---|---|---|---|
| Median female unemployment | 9.0% | 6.7% | 6.0% | 5.6% | 4.8% |

Tract-level correlations with the female rate: poverty share **+0.32**, median
household income **−0.23**, Asian non-Hispanic share **−0.17**, Black
non-Hispanic share **+0.15**, bachelor's-or-higher share **−0.13**.

Geographically, the high-rate concentrations are the Antelope Valley
(Lancaster–Palmdale) in the north and a broad band across South LA — visible in
both panels of the figure.

## The caveat that matters most

**These are survey estimates, and at tract level they are very noisy.** A
five-year tract estimate rests on roughly 250 sampled housing units; once you
narrow to *women*, *in the labor force*, and *unemployed*, the underlying counts
are often in the low dozens.

Computing the coefficient of variation for every tract. Of the 2,463 analyzable
tracts, 2,393 have a defined CV; the other 70 estimate female unemployment at
exactly 0%, which makes a *relative* error undefined — that is an artefact of a
zero point estimate, not evidence of precision.

| CV band | Census Bureau reading | Tracts |
|---|---|---|
| ≤ 15% | reliable | **1** |
| 15–30% | usable | 40 |
| 30–40% | weak | 330 |
| > 40% | unreliable | **2,022 (84%)** |
| *undefined* | *rate estimated at exactly 0%* | *70* |

Median CV is **55%**. So:

- Do not read a single tract's rate as a precise number. The app's click panel
  shows the 90% confidence interval instead — for most tracts it is wide enough
  to span several of the map's colour bands.
- Two adjacent tracts that differ on the map usually cannot be distinguished
  statistically.
- The *patterns* — the income gradient above, the Antelope Valley and South LA
  concentrations — are trustworthy in a way individual tract values are not,
  because they pool hundreds of tracts.
- The app's **maximum CV** slider keeps only well-measured tracts. This is
  honest but not neutral: low CV correlates with a *high* rate (the CV of a
  proportion falls as the proportion rises), so filtering hard biases the
  surviving sample upward. Watch the median move as you drag it.

Other limitations: five-year estimates are a 2020–2024 *average* spanning the
pandemic shock and recovery, not a 2024 snapshot; ACS records sex as a binary
item, so "women" means everyone the survey classified as female; 25 LA tracts
have no women in the civilian labor force at all (jails, hospital campuses,
industrial and port land) and are suppressed, as are tracts with fewer than 50
by default.

## Related academic work

Two literatures bear on this analysis.

**Spatial determinants of women's employment in Los Angeles.** The closest
direct precedent is Ong & Miller, *Spatial and Transportation Mismatch in Los
Angeles* (Journal of Planning Education and Research 25:43–56, 2005), which runs
tract-level regressions of employment ratios and unemployment rates on job
accessibility and car ownership for exactly this county. Their gendered finding
is the relevant one: areas with more nearby jobs raise *female* employment rates
but not male ones, and transportation mismatch — lack of a car — mattered more
than spatial mismatch for poor neighbourhoods. Blumenberg and colleagues at UCLA
have extended the car-access strand ([The Drive to Work](https://doi.org/10.1177/0739456x16633501),
JPER 2017; [job accessibility by income group](https://link.springer.com/article/10.1007/s11116-016-9708-4),
Transportation 2017). On the wage side, [The Spatial Determinants of Wage
Inequality: Evidence from Recent Latina Immigrants in Southern
California](https://www.tandfonline.com/doi/abs/10.1080/13545700902748250)
(Feminist Economics 15(2), 2009) works the same geography for women specifically.
More recent work applies the spatial-mismatch frame to women's unemployment
directly — see [Spatial Mismatch, Race and Ethnicity, and Unemployment:
Implications for Interventions With Women on Probation and
Parole](https://www.researchgate.net/publication/354611089_Spatial_Mismatch_Race_and_Ethnicity_and_Unemployment_Implications_for_Interventions_With_Women_on_Probation_and_Parole)
(Crime & Delinquency, 2021), which finds job density within two miles of a
woman's tract mediates the minority-status/unemployment relationship, moderated
by transport access.

**How much to trust a tract estimate.** This is the literature behind the CV
table above, and it is unusually worth reading before publishing tract maps.
Spielman, Folch & Nagle, [Patterns and causes of uncertainty in the American
Community Survey](https://pubmed.ncbi.nlm.nih.gov/25404783/) (Applied Geography
46:147–157, 2014) show tract-level ACS margins run ~75% larger than the
decennial long-form estimates they replaced, and — directly relevant here — that
data quality is itself correlated with tract income, so the noise is not
randomly distributed across the map. Spielman & Folch, [Reducing Uncertainty in
the American Community Survey through Data-Driven
Regionalization](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0115626)
(PLOS ONE 10(2), 2015) offer the standard fix: pool tracts into composite
regions until the margins are tolerable. Spielman & Singleton, [Studying
Neighborhoods Using Uncertain Data from the American Community Survey: A
Contextual Approach](https://www.tandfonline.com/doi/full/10.1080/00045608.2015.1052335)
(Annals of the AAG 105(5), 2015) argue for composites of several variables
rather than one noisy indicator. Logan et al., [Models for Small Area Estimation
for Census Tracts](https://onlinelibrary.wiley.com/doi/abs/10.1111/gean.12215)
(Geographical Analysis 52(3), 2020) compare the model-based smoothers.

If this analysis were headed for publication rather than exploration, the
literature points at three concrete next steps: regionalize or spatially smooth
before mapping; model the rate hierarchically with tract-level MOEs as known
sampling variance rather than treating point estimates as data; and add job
accessibility and vehicle-availability covariates (ACS table B08201), which is
where the LA-specific literature says the explanatory power actually sits.

## Sources

A standalone PDF documenting where every input came from and how it was
processed is at [`report/data_sources.pdf`](report/data_sources.pdf).

- [ACS 5-Year Data (2009–2024), Census developer documentation](https://www.census.gov/data/developers/data-sets/acs-5year.html)
- [ACS table-based summary files, 2024](https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/)
- [TIGER/Line 2024 census tract shapefiles](https://www2.census.gov/geo/tiger/TIGER2024/TRACT/)
- [ACS General Handbook ch. 7, understanding error and determining statistical significance](https://www.census.gov/content/dam/Census/library/publications/2018/acs/acs_general_handbook_2018_ch07.pdf)
- [Census Bureau guidance for labor force statistics data users](https://www.census.gov/topics/employment/labor-force/guidance.html)
- [Census Bureau small area estimation research](https://www.census.gov/topics/research/stat-research/expertise/small-area-est.html)
