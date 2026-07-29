### What this app shows

Every census tract in Los Angeles County, from the **American Community Survey
2020–2024 five-year estimates** — the most recent ACS release with tract-level
detail (published December 2025).

**Female unemployment rate** = women aged 16 and over who are unemployed,
divided by women aged 16 and over in the *civilian* labor force, summed across
every age band in ACS table **B23001**. This is the standard unemployment-rate
definition: women in the Armed Forces are excluded from both the numerator and
the denominator, and women who are not in the labor force at all (retired, in
school, caregiving, discouraged) are excluded from the denominator — so a low
rate here does not by itself mean a neighbourhood where many women work.

Table **S2301** publishes a ready-made female rate, but only for ages 20–64.
Building the measure from B23001 covers the full 16-and-over population and
makes the margins of error aggregable.

### Read the margins of error before you read the map

A five-year ACS tract estimate rests on roughly 250 sampled housing units spread
over five years. Once you narrow to *women*, *in the labor force*, and
*unemployed*, the counts behind a single tract's rate are often in the low
dozens.

In this file the median tract's female unemployment rate has a **coefficient of
variation near 55%**, and **2,022 of the 2,393 tracts with a defined CV (84%)**
exceed the 40% threshold at which the Census Bureau's own guidance treats an
estimate as unreliable. A further 70 tracts estimate the rate at exactly 0%,
leaving the CV undefined — an artefact of a zero point estimate, not precision.
The practical consequences:

- A single tract's rate is indicative, not precise. Use the click panel's 90%
  confidence interval, not the point estimate.
- Differences between two adjacent tracts are usually not statistically
  distinguishable.
- Broad spatial *patterns* — the Antelope Valley, South LA — are trustworthy in
  a way that individual tract values are not, because they pool many tracts.
- The **Maximum coefficient of variation** slider lets you keep only the
  well-measured tracts. Doing so is honest but not neutral: it preferentially
  drops small and low-labor-force tracts, so the surviving sample is not
  representative of the county.

### Other caveats

- Five-year estimates are a 2020–2024 *average*, not a 2024 snapshot. They
  straddle the pandemic labor-market shock and its recovery.
- ACS records sex as a binary male/female item. "Women" here means everyone the
  survey classified as female; the data cannot speak to non-binary or
  transgender respondents.
- Tract boundaries are the 2020 vintage used throughout the 2020–2024 file.
- Tracts with fewer than 50 women in the civilian labor force are filtered out
  by default. Twenty-five LA County tracts have none at all — these are jails,
  hospital campuses, industrial land, and port areas.
- The Channel Islands (Santa Catalina, San Clemente) are dropped from the map
  because they would triple its height; they remain in the data table.
