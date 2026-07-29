/*===========================================================================*
 * la_female_unemployment.sas
 *
 * Reproduces, in SAS, the Los Angeles County female-unemployment analysis
 * built by R/01_build_data.R and R/02_plot.R.
 *
 *   Source : U.S. Census Bureau, American Community Survey 2020-2024
 *            5-year estimates, table B23001 (sex by age by employment status),
 *            distributed as the public "table-based summary file".
 *   Geography: all 2,498 census tracts in Los Angeles County, California
 *            (state 06, county 037).
 *   Measure: female unemployment rate = women 16+ unemployed divided by
 *            women 16+ in the CIVILIAN labor force, summed over all age bands.
 *
 * No Census API key is required: the summary files are static downloads.
 * (The api.census.gov data endpoints now do require a key -- see the
 *  commented alternative at the bottom of this file.)
 *
 * Tested against: SAS 9.4M7 / Viya. Requires PROC HTTP. The choropleth needs
 * SAS/GRAPH (PROC GMAP) or SAS 9.4M5+ (PROC SGMAP); both versions are given.
 *===========================================================================*/

%let year    = 2024;
%let state   = 06;
%let county  = 037;
%let geopfx  = 1400000US&state.&county.;        /* tract GEO_ID prefix        */
%let workdir = %sysfunc(pathname(work));        /* scratch space for downloads*/

libname out "."; /* <-- point at wherever you want the permanent datasets */

/*---------------------------------------------------------------------------*
 * 1. Download the national B23001 summary file (~305 MB) and the four
 *    correlate tables. Each is pipe-delimited with a one-line header.
 *---------------------------------------------------------------------------*/
%macro getsf(tbl);
  filename _sf "&workdir./&tbl..dat";
  proc http
    url="https://www2.census.gov/programs-surveys/acs/summary_file/&year./table-based-SF/data/5YRData/acsdt5y&year.-%lowcase(&tbl.).dat"
    method="GET" out=_sf;
  run;
  %if &SYS_PROCHTTP_STATUS_CODE ne 200 %then
    %put %str(ER)ROR: download of &tbl. failed, HTTP &SYS_PROCHTTP_STATUS_CODE.;
%mend;

%getsf(B23001); %getsf(B19013); %getsf(B03002); %getsf(B17001); %getsf(B15003);

/*---------------------------------------------------------------------------*
 * 2. Read B23001, keeping only Los Angeles County tracts.
 *
 *    Column layout is fixed: GEO_ID, then E001 M001 E002 M002 ... E173 M173.
 *    So estimate n sits in field 2n and its margin of error in field 2n+1;
 *    after GEO_ID is consumed those become v[2n-1] and v[2n].
 *
 *    Census writes -666666666 (and friends) for "not available".
 *---------------------------------------------------------------------------*/
%let nvar = 173;
%let nfld = %eval(2*&nvar.);   /* 346 numeric fields after GEO_ID */

data b23001;
  infile "&workdir./B23001.dat" dlm='|' dsd truncover firstobs=2 lrecl=32767;
  length geo_id $24;
  array v[&nfld.] _temporary_;
  array e[&nvar.] e1-e&nvar.;   /* estimates      */
  array m[&nvar.] m1-m&nvar.;   /* margins of error */
  input geo_id $ v[*];
  if substr(geo_id,1,%length(&geopfx.)) ne "&geopfx." then delete;
  do i = 1 to &nvar.;
    e[i] = v[2*i-1];  m[i] = v[2*i];
    if e[i] <= -666666666 then e[i] = .;
    if m[i] <= -666666666 then m[i] = .;
  end;
  geoid = substr(geo_id, 10);          /* strip the "1400000US" summary prefix */
  keep geoid e1-e&nvar. m1-m&nvar.;
run;

/*---------------------------------------------------------------------------*
 * 3. Build the rates.
 *
 *    B23001 line numbers. Ages 16-64 split the labor force into Armed Forces
 *    vs Civilian, so the civilian labor force is read off the "Civilian:"
 *    line. Ages 65+ have no Armed Forces line, so "In labor force:" already
 *    IS the civilian total.
 *---------------------------------------------------------------------------*/
%let f_civ  = 92 99 106 113 120 127 134 141 148 155;   /* female 16-64 civilian LF */
%let f_lf65 = 160 165 170;                             /* female 65+ in LF          */
%let f_une  = 94 101 108 115 122 129 136 143 150 157 162 167 172;
%let m_civ  = 6 13 20 27 34 41 48 55 62 69;
%let m_lf65 = 74 79 84;
%let m_une  = 8 15 22 29 36 43 50 57 64 71 76 81 86;

/* --- sums of estimates, and ACS aggregation of their margins of error ---
   Handbook ch. 8: the MOE of a sum is the root sum of squares of the
   component MOEs, counting only ONE zero-estimate cell -- the largest --
   so that long runs of empty age cells do not inflate the result.
   Note "&outest + e[..]" is the SAS sum statement, which ignores missings
   and retains across the accumulation.                                     */
%macro aggsum(outest, outmoe, lines);
  &outest = 0; _ss = 0; _zmax = 0;
  %local k L;
  %let k = 1;
  %do %while (%scan(&lines., &k.) ne );
    %let L = %scan(&lines., &k.);
    if not missing(e[&L.]) then do;
      &outest = &outest + e[&L.];
      if e[&L.] = 0 then _zmax = max(_zmax, abs(coalesce(m[&L.],0)));
      else               _ss   = _ss + abs(coalesce(m[&L.],0))**2;
    end;
    %let k = %eval(&k.+1);
  %end;
  &outmoe = sqrt(_ss + _zmax**2);
%mend;

/* --- rate, and the MOE of a proportion --------------------------------
   Handbook ch. 8. If the radicand goes negative the numerator is not a
   subset of the denominator in the sampling sense; the documented fallback
   is the ratio formula (a plus instead of a minus).                      */
%macro rate(num, nmoe, den, dmoe, rt, rmoe);
  if &den. > 0 then do;
    &rt. = 100 * &num. / &den.;
    _p = &num. / &den.;
    _in = &nmoe.**2 - (_p**2)*(&dmoe.**2);
    if _in < 0 then _in = &nmoe.**2 + (_p**2)*(&dmoe.**2);
    &rmoe. = 100 * sqrt(_in) / &den.;
  end;
  else do; &rt. = .; &rmoe. = .; end;
%mend;

data rates;
  set b23001;
  array e[&nvar.] e1-e&nvar.;
  array m[&nvar.] m1-m&nvar.;

  %aggsum(female_clf,   female_clf_moe,   &f_civ. &f_lf65.)
  %aggsum(female_unemp, female_unemp_moe, &f_une.)
  %aggsum(male_clf,     male_clf_moe,     &m_civ. &m_lf65.)
  %aggsum(male_unemp,   male_unemp_moe,   &m_une.)

  %rate(female_unemp, female_unemp_moe, female_clf, female_clf_moe, unemp_rate_f, unemp_rate_f_moe)
  %rate(male_unemp,   male_unemp_moe,   male_clf,   male_clf_moe,   unemp_rate_m, unemp_rate_m_moe)

  gap_f_minus_m = unemp_rate_f - unemp_rate_m;

  /* Coefficient of variation. ACS margins are at 90% confidence, so
     SE = MOE / 1.645. Census guidance calls CV > 30-40% unreliable.        */
  if unemp_rate_f > 0 then cv_f = (unemp_rate_f_moe / 1.645) / unemp_rate_f * 100;

  tract = substr(geoid, 6, 6);
  label unemp_rate_f = "Female unemployment rate (%)"
        unemp_rate_m = "Male unemployment rate (%)"
        gap_f_minus_m= "Female minus male (pct. points)"
        cv_f         = "Coefficient of variation of the female rate (%)"
        female_clf   = "Women 16+ in the civilian labor force";
  keep geoid tract female_clf female_unemp male_clf male_unemp
       unemp_rate_f unemp_rate_f_moe unemp_rate_m unemp_rate_m_moe
       gap_f_minus_m cv_f;
run;

/*---------------------------------------------------------------------------*
 * 4. Correlates: income, poverty, education, race and ethnicity.
 *---------------------------------------------------------------------------*/
%macro readsf(tbl, nvar, keeplist);
  data _&tbl.;
    infile "&workdir./&tbl..dat" dlm='|' dsd truncover firstobs=2 lrecl=32767;
    length geo_id $24;
    array v[%eval(2*&nvar.)] _temporary_;
    array e[&nvar.] &tbl._1-&tbl._&nvar.;
    input geo_id $ v[*];
    if substr(geo_id,1,%length(&geopfx.)) ne "&geopfx." then delete;
    do i = 1 to &nvar.;
      e[i] = v[2*i-1];
      if e[i] <= -666666666 then e[i] = .;
    end;
    geoid = substr(geo_id, 10);
    keep geoid &keeplist.;
  run;
%mend;

%readsf(B19013,  1, B19013_1)
%readsf(B03002, 21, B03002_1 B03002_3 B03002_4 B03002_6 B03002_12)
%readsf(B17001, 59, B17001_1 B17001_2)
%readsf(B15003, 25, B15003_1 B15003_22 B15003_23 B15003_24 B15003_25)

proc sort data=rates;    by geoid; run;
proc sort data=_B19013;  by geoid; run;
proc sort data=_B03002;  by geoid; run;
proc sort data=_B17001;  by geoid; run;
proc sort data=_B15003;  by geoid; run;

data out.la_female_unemployment;
  merge rates(in=a) _B19013 _B03002 _B17001 _B15003;
  by geoid;
  if a;
  median_hh_income = B19013_1;
  if B17001_1 > 0 then pct_poverty        = 100 * B17001_2 / B17001_1;
  if B15003_1 > 0 then pct_bachelors_plus = 100 * (B15003_22+B15003_23+B15003_24+B15003_25) / B15003_1;
  total_pop = B03002_1;
  if total_pop > 0 then do;
    pct_hispanic = 100 * B03002_12 / total_pop;
    pct_white_nh = 100 * B03002_3  / total_pop;
    pct_black_nh = 100 * B03002_4  / total_pop;
    pct_asian_nh = 100 * B03002_6  / total_pop;
  end;
  label median_hh_income="Median household income ($)" pct_poverty="Share in poverty (%)"
        pct_bachelors_plus="Share with a bachelor's degree or more (%)"
        pct_hispanic="Share Hispanic or Latino (%)";
  drop B19013_: B03002_: B17001_: B15003_:;
run;

/* Analysis sample: suppress tracts with a labor force too small for the rate
   to mean anything (25 LA tracts have no women in the labor force at all --
   jails, hospital campuses, industrial land, port areas).                   */
data analysis;
  set out.la_female_unemployment;
  where female_clf >= 50 and not missing(unemp_rate_f);
run;

/*---------------------------------------------------------------------------*
 * 5. Descriptive statistics
 *---------------------------------------------------------------------------*/
title "Female unemployment across Los Angeles County census tracts";
title2 "ACS 2020-2024 5-year estimates, table B23001";

proc means data=analysis n nmiss mean std min p5 p10 q1 median q3 p90 p95 max maxdec=2;
  var unemp_rate_f unemp_rate_m gap_f_minus_m female_clf cv_f;
run;

/* Labor-force weighted mean -- the county-level rate, as opposed to the mean
   of the tract rates, which weights a 40-worker tract like a 4,000-worker one. */
proc means data=analysis sum noprint;
  var female_unemp female_clf;
  output out=_cty sum(female_unemp)=u sum(female_clf)=l;
run;
data _null_; set _cty;
  county_rate = 100 * u / l;
  put "County-wide female unemployment rate: " county_rate 5.2 "%";
run;

proc univariate data=analysis noprint;
  var unemp_rate_f;
  histogram unemp_rate_f / endpoints=0 to 45 by 1 odstitle="Distribution across tracts";
  inset n mean median std q1 q3 / position=ne;
run;

proc corr data=analysis pearson spearman nosimple;
  var unemp_rate_f;
  with median_hh_income pct_poverty pct_bachelors_plus
       pct_hispanic pct_black_nh pct_white_nh pct_asian_nh;
run;

/* How reliable is any single tract's rate? */
data _rel; set analysis;
  length band $28;
  if      cv_f <= 15 then band = "1 reliable   (CV <= 15%)";
  else if cv_f <= 30 then band = "2 usable     (CV 15-30%)";
  else if cv_f <= 40 then band = "3 weak       (CV 30-40%)";
  else                    band = "4 unreliable (CV > 40%)";
run;
proc freq data=_rel; tables band / nocum;
  title3 "Reliability of the tract-level female unemployment rate";
run;
title3;

/* Female rate by quintile of tract median household income */
proc rank data=analysis out=_q groups=5;
  var median_hh_income; ranks inc_quintile;
run;
proc means data=_q n mean median std maxdec=2;
  class inc_quintile;
  var unemp_rate_f;
  title3 "Female unemployment rate by quintile of tract median household income";
run;
title3;

/*---------------------------------------------------------------------------*
 * 6. Graphics
 *---------------------------------------------------------------------------*/
ods graphics on / width=10in height=7in imagename="la_female_unemployment";

/* 6a. Distribution */
proc sgplot data=analysis noautolegend;
  histogram unemp_rate_f / binwidth=1 fillattrs=(color=CX3987E5) scale=count;
  refline 6.24 / axis=x lineattrs=(color=CXE34948 thickness=2)
                 label="county tract median" labelloc=inside;
  xaxis label="Female unemployment rate (%)" values=(0 to 40 by 5);
  yaxis label="Census tracts" grid;
  title3 "Distribution of the female unemployment rate across 2,463 tracts";
run;

/* 6b. Female vs male */
proc sgplot data=analysis;
  scatter x=unemp_rate_m y=unemp_rate_f / markerattrs=(symbol=circlefilled size=5 color=CX256ABF)
                                          transparency=0.7;
  lineparm x=0 y=0 slope=1 / lineattrs=(color=CX52514E pattern=shortdash)
                             legendlabel="equal rates";
  xaxis label="Male unemployment rate (%)" values=(0 to 40 by 5) grid;
  yaxis label="Female unemployment rate (%)" values=(0 to 40 by 5) grid;
  title3 "Female against male unemployment rate, by tract";
run;

/* 6c. Female rate against tract poverty */
proc sgplot data=analysis;
  scatter x=pct_poverty y=unemp_rate_f / markerattrs=(symbol=circlefilled size=5 color=CX256ABF)
                                         transparency=0.75;
  reg     x=pct_poverty y=unemp_rate_f / lineattrs=(color=CXE34948 thickness=2) nomarkers clm;
  xaxis label="Share of the tract population in poverty (%)" grid;
  yaxis label="Female unemployment rate (%)" grid;
  title3 "Female unemployment against tract poverty";
run;
title3;

/*---------------------------------------------------------------------------*
 * 6d. The choropleth.
 *     Geometry is the Census TIGER/Line 2024 tract shapefile for California.
 *---------------------------------------------------------------------------*/
filename tgr "&workdir./ca_tracts.zip";
proc http url="https://www2.census.gov/geo/tiger/TIGER&year./TRACT/tl_&year._&state._tract.zip"
     method="GET" out=tgr;
run;

/* Unzip (SAS 9.4M5+). On older releases, unzip outside SAS and skip this step. */
%macro unzip_member(mem);
  filename src zip "&workdir./ca_tracts.zip" member="&mem.";
  filename dst "&workdir./&mem.";
  data _null_;
    infile src recfm=n; file dst recfm=n;
    input byte $char1. @@; put byte $char1. @@;
  run;
  filename src clear; filename dst clear;
%mend;
%unzip_member(tl_&year._&state._tract.shp)
%unzip_member(tl_&year._&state._tract.shx)
%unzip_member(tl_&year._&state._tract.dbf)
%unzip_member(tl_&year._&state._tract.prj)

proc mapimport datafile="&workdir./tl_&year._&state._tract.shp" out=ca_map;
run;

data la_map;
  set ca_map;
  where COUNTYFP = "&county."
    and substr(GEOID,1,7) ne "0603759";   /* drop the offshore Channel Islands */
  rename GEOID = geoid;
run;
proc sort data=la_map; by geoid segment; run;

/* Response data must carry the same ID variable as the map. */
data mapresp;
  set analysis;
  keep geoid unemp_rate_f;
run;
proc sort data=mapresp; by geoid; run;

/* --- PROC SGMAP (SAS 9.4M5 and later) ---------------------------------- */
proc sgmap mapdata=la_map maprespdata=mapresp;
  choromap unemp_rate_f / mapid=geoid id=geoid
           lineattrs=(thickness=0) name="c";
  gradlegend "c" / title="Female unemployment rate (%)";
  title3 "Female unemployment rate by census tract, Los Angeles County";
run;

/* --- PROC GMAP alternative (SAS/GRAPH), with the same six-class scheme
       used by the R figure -----------------------------------------------
pattern1 v=s c=CXCDE2FB; pattern2 v=s c=CX9EC5F4; pattern3 v=s c=CX6DA7EC;
pattern4 v=s c=CX3987E5; pattern5 v=s c=CX256ABF; pattern6 v=s c=CX104281;

data mapresp2; set mapresp;
  length band $12;
  if      unemp_rate_f <  3   then band="1 under 3%";
  else if unemp_rate_f <  5   then band="2 3-5%";
  else if unemp_rate_f <  7.5 then band="3 5-7.5%";
  else if unemp_rate_f < 10   then band="4 7.5-10%";
  else if unemp_rate_f < 15   then band="5 10-15%";
  else                             band="6 15%+";
run;
proc gmap map=la_map data=mapresp2 all;
  id geoid;
  choro band / discrete coutline=same;
run;
--------------------------------------------------------------------------- */
title3;
ods graphics off;

/*---------------------------------------------------------------------------*
 * ALTERNATIVE INPUT: the Census API.
 *
 * api.census.gov now requires a free key (https://api.census.gov/data/key_signup.html).
 * With one, the table pull above collapses to a single request per 50 variables
 * and returns JSON, which the JSON libname engine reads directly:
 *
 *   %let key = YOUR_KEY_HERE;
 *   filename resp temp;
 *   proc http
 *     url="https://api.census.gov/data/&year./acs/acs5?get=group(B23001)%nrstr(&)for=tract:*%nrstr(&)in=state:&state.%nrstr(&)in=county:&county.%nrstr(&)key=&key."
 *     method="GET" out=resp;
 *   run;
 *   libname j json fileref=resp;
 *
 * The JSON engine surfaces the response as ROOT with one observation per row;
 * the first row is the header. Everything downstream of step 3 is unchanged.
 *
 * The subject table S2301 publishes a ready-made female unemployment rate
 * (S2301_C04_023E) but only for ages 20-64. Building the measure from B23001
 * as above covers the full 16-and-over population and lets the margins of
 * error be aggregated properly.
 *---------------------------------------------------------------------------*/
