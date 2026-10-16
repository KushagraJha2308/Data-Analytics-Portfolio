# Netflix Engagement Analysis: where does the next hour of viewing come from?

An end-to-end analysis of three consecutive Netflix *What We Watched* engagement reports
(January 2025 – June 2026): **289 billion hours viewed across 22,351 titles**.

**Stack:** Python (pandas, statsmodels, SciPy) · SQL (SQLite, star schema, window functions) · Power BI (DAX)

## The business question

Netflix's total viewing is almost flat: 95.2B → 95.5B → 96.8B hours per half-year. A content
strategy team looking only at that headline would conclude nothing is changing. This project
looks underneath it to answer: **what actually sustains viewing, and how should title
performance be judged?**

## Key findings

| # | Finding | So what |
|---|---|---|
| 1 | **43% of viewing has to be replaced every half-year.** 41B hours decay or leave; new releases cover under half of that gap (18B). | Growth of +1.4% is the small difference between two very large numbers. The slate should be planned against the replacement gap. |
| 2 | **New releases are 2.8% of titles but 18.5% of hours** (6.7× their share). Even so, about 80% of viewing is catalogue and **half of all hours are licensed titles**. | Licensing protects half of engagement. 11 of the top 20 franchises are licensed. |
| 3 | **A new season lifts the earlier seasons by a median +59%** versus 0% for shows without a launch (p < 0.001, 95% CI +45% to +70%). | 100 season launches added ~3.0B hours to their own back catalogue. Renewal value is larger than the new season's own numbers. |
| 4 | **Half-year rankings undersell late launches.** A title launched in month 1 carries only ~13% of its views into the next period; a month-6 launch carries 40–51%. | Launch-period rank is the wrong scorecard for anything released in the last two months. |
| 5 | **The metric changes the story.** Movies are 24% of hours but 55% of views. | "Top title" depends on the metric: hours measures time spent, views measures reach. |
| 6 | **A fifth of the catalogue delivers 80% of hours** (21% of shows, 18% of movies). | Classic Pareto. Movie concentration is slowly falling (top-decile share 69% → 66%). |

<p>
  <img src="reports/figures/04_viewing_bridge.png" width="49%">
  <img src="reports/figures/06_franchise_halo.png" width="49%">
</p>
<p>
  <img src="reports/figures/05_launch_month_carry_over.png" width="49%">
  <img src="reports/figures/03_release_cohort_efficiency.png" width="49%">
</p>

Full analysis with code and commentary: [`notebooks/netflix_engagement_analysis.ipynb`](notebooks/netflix_engagement_analysis.ipynb)

## Recommendations

1. **Value renewals on franchise hours, not new-season hours.** Include the back-season halo in the renewal case.
2. **Replace launch-period rank with a timing-adjusted view** (fixed 90-day window, or performance against launch-date expectation).
3. **Track licence expiries against hours at risk.** Licensed content is core, not filler.
4. **Where there is a choice, favour limited series and global rights.** Limited series launch about 2× stronger than other launches; global availability is the largest single factor (about 5×), all else equal.

## How it works

```
3 Excel reports ──► extract ──► clean + validate ──► star schema ──► SQL analysis ──► notebook (stats, charts)
  (raw, messy)      src/extract   src/transform       SQLite + CSV     sql/*.sql  └──► Power BI (DAX)
```

**Data model**

```
dim_period ──┐
             ├──► fact_engagement  (1 row per title per period, 50,019 rows)
dim_title  ──┘
dim_date ──► dim_title.release_date          fact_other_viewing (titles under 50K views)
```

### Data cleaning: what the raw files needed

The source is formatted for reading, not analysis. The pipeline handles:

| Issue | Treatment |
|---|---|
| Banner rows, blank column and footnotes inside the data | Header located dynamically; pipeline fails loudly if the layout changes |
| Aggregate "Other" rows mixed with titles (1.6B hours) | Moved to a separate fact table |
| Title text is not unique ("Maria" 2019 vs "Maria" 2024) | Natural key = content type + title + release date |
| Runtime as `*` (1.1% of rows) | Kept as NULL, never imputed |
| Runtime as `2:25*` | Parsed. The asterisk marks **live events**; kept as a feature |
| Release date missing on 65% of rows | Netflix publishes a premiere date only for its own releases, so blank = licensed |
| No language, genre or franchise columns | Franchise and season parsed from the title; language group inferred from the script of the native title |

**Trust in the numbers.** The pipeline asserts that hours in the model equal hours in the
source files. `sql/03_data_quality_checks.sql` runs 11 checks after every load (6 hard
failures, 5 monitored warnings). 22 unit tests cover the parsing rules. Total hours including
the "Other" rows (97.7B for 2026 H1) match Netflix's published "over 97 billion".

### SQL

[`sql/04_business_analysis.sql`](sql/04_business_analysis.sql) answers 14 business questions.
Techniques used: CTEs, window functions (`LAG`, `NTILE`, `DENSE_RANK`, running totals with
frame clauses, named windows), self-joins for period-over-period change, `NOT EXISTS`
anti-joins, and conditional aggregation. Results are exported to `reports/sql_outputs/`.

### Python

- **ETL** in `src/` (extract / transform / load), run with one command.
- **Statistics:** Gini and Lorenz curves, Mann-Whitney U test with a bootstrap confidence
  interval for the halo effect, log-linear OLS with robust (HC3) standard errors for launch drivers.

### Power BI

Open [`powerbi/NetflixEngagement.pbip`](powerbi/NetflixEngagement.pbip) in Power BI Desktop.
Star-schema model, 35 DAX measures in [`powerbi/measures.dax`](powerbi/measures.dax)
(period-over-period, share-of-total, efficiency index) and four report pages: Overview,
Catalogue, Launches, Franchises. Details: [`powerbi/BUILD_GUIDE.md`](powerbi/BUILD_GUIDE.md).

<!-- Add dashboard screenshots here once the .pbix is built -->

## Run it

```bash
pip install -r requirements.txt
python run_pipeline.py      # raw Excel -> validated star schema (SQLite + CSV)
python run_sql.py           # data-quality checks + 14 business queries
python -m pytest            # 22 unit tests
jupyter notebook notebooks/netflix_engagement_analysis.ipynb
```

## Limitations

- **Three half-year snapshots.** No weekly curves, no subscriber, country or revenue data.
- **Observational.** The halo and launch-driver results are associations. Renewed shows are
  already the stronger ones, and launches come with marketing.
- **Inferred fields.** Licensed status (blank release date) and language (title script) are
  not published by Netflix. The language rule finds 26% non-English hours against Netflix's
  stated "over one-third", so it is a lower bound: Latin-script titles listed without a
  separate English title cannot be detected.
- **Truncated tail.** Views are rounded to 100K and titles under 50K views are aggregated.

## Data source

Netflix, *What We Watched: A Netflix Engagement Report* (2025 H1, 2025 H2, 2026 H1), published at
[about.netflix.com](https://about.netflix.com/en/news/what-we-watched-the-first-half-of-2026).
This is an independent analysis and is not affiliated with Netflix.

## Author

**Kushagra Jha** · Data Analyst · [LinkedIn](https://www.linkedin.com/in/ADD-YOUR-ID)
