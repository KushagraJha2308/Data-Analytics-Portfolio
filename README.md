# One Nation One Ration Card: who uses ration portability, and where is it missing?

A state-level analysis of India's ration portability scheme using eight official datasets
from data.gov.in (2020–2026, 36 States/UTs, 396 million transactions in 2025).

**Stack:** Python (pandas, statsmodels, scikit-learn) · SQL (SQLite, window functions) · Machine learning (clustering)

## The question

Under One Nation One Ration Card (ONORC), a ration card works at any fair price shop in
India, so a migrant worker can collect subsidised grain where they live. A *portability
transaction* is a ration drawn away from the card's home shop, inside the state or in
another state. **Is the scheme reaching the places where migrants actually are?**

## Key findings

| # | Finding | So what |
|---|---|---|
| 1 | **Portability grew 52% in two years** (260M → 396M transactions). Excluding two states that only started reporting mid-period, real growth is **43%**. | Headline growth overstates adoption. Growth should be reported like-for-like. |
| 2 | **It is almost entirely intra-state.** Only 2.2% of transactions happen in a different state. | ONORC is mainly used by people moving inside their own state, not by inter-state migrants. |
| 3 | **Bihar alone is 33% of all transactions**; the top five states are 65%. | National averages describe a handful of states. |
| 4 | **Inter-state use does follow migrants** (rank correlation 0.75, p < 0.001; elasticity 1.47 after controlling for state size). | The scheme works in the direction intended. |
| 5 | **But Delhi handles 65% of all inter-state transactions**: about 110 per registered migrant, five times Maharashtra or Haryana. | One city-state is the working model; the rest lag. |
| 6 | **Under-served destinations:** Uttar Pradesh records 636 inter-state transactions for 18,443 registered migrants; Tamil Nadu, Punjab and Gujarat are also far below expectation. Karnataka reports no figure. | These are where awareness, shop compliance or reporting should be checked first. |
| 7 | **Three types of state** from k-means clustering: home-state users (15), destination hubs (8), and a reporting gap (Himachal Pradesh, Meghalaya). | Each type needs a different response. |
| 8 | **Entitlement check:** 5.19 kg per beneficiary per month nationally, but 3.96 kg in Sikkim and 4.47 kg in Punjab. | Candidates for a delivery audit. |

<p>
  <img src="reports/figures/03_interstate_vs_migrants.png" width="49%">
  <img src="reports/figures/05_state_clusters.png" width="49%">
</p>
<p>
  <img src="reports/figures/02_state_concentration.png" width="49%">
  <img src="reports/figures/04_underserved_destinations.png" width="49%">
</p>

Full analysis: [`notebooks/onorc_analysis.ipynb`](notebooks/onorc_analysis.ipynb)

## Recommendations

1. **Target under-served destinations first**: Uttar Pradesh, Tamil Nadu, Punjab, Gujarat.
2. **Fix reporting before measuring**: Karnataka and Arunachal Pradesh publish no inter-state figure; Himachal Pradesh fell from 117,699 transactions to 31 in a year.
3. **Study Delhi as the working model.**
4. **Report growth like-for-like**, excluding states that join mid-period.
5. **Audit entitlement delivery** in Sikkim and Punjab.

## How it works

```
8 CSV files (data.gov.in) ──► extract ──► conform state names ──► reconcile to published totals ──► model ──► SQL ──► notebook
   different layouts          long format   alias table            24 totals checked              SQLite     11 queries   stats + clustering
```

**Data model:** `dim_state` (36 rows, with region and 2026 snapshot attributes) and
`fact_state_year` (200 rows: one per State/UT per year, 2020–2025).

### The data

The catalog this project started from,
[One Nation One Ration Card (ONORC) Plan](https://data.gov.in/catalog/one-nation-one-ration-card-onorc-plan),
holds one table: monthly inter-state transactions for 2022–23. When this was built the
data.gov.in API server was refusing connections, so that file could not be downloaded. The
project uses eight newer tables from the same portal instead, all published as answers to
questions in Parliament. Sources and resource IDs are in
[`data/reference/source_manifest.csv`](data/reference/source_manifest.csv).

| Table | Period |
|---|---|
| Portability transactions under NFSA | 2023–2025 |
| Inter-state portability transactions under ONORC | 2024–2025 |
| NFSA beneficiaries and foodgrain distributed | 2023–2025 |
| NFSA beneficiaries by category (AAY, PHH) | March 2026 |
| Ration cards deleted (three separate sources) | 2020–2025 |
| Urban migrant workers on eShram, by state of work and state of origin | January 2026 |
| Unorganised workers registered on eShram | 2025–2026 |
| Transit losses of foodgrain | April–December 2025 |

### Data cleaning

| Issue | Treatment |
|---|---|
| "Total" rows inside the data | Separated and used as a check: states must add up to the published total (24 totals, largest gap 3 in 396 million) |
| Misspelt state name ("Dadar and Nagar Haveli…") | Alias table maps every spelling to one master name; an unknown name stops the pipeline |
| A row that is not a state ("NEF Shillong", an FCI office) | Excluded and logged |
| Three sources for deleted ration cards | Cross-checked on 277 overlapping state-years: zero conflicts |
| States joining the system mid-period (20× jump) | Flagged and excluded from growth rates |
| Missing values | Kept as missing, never filled with zero |
| No grain data for Chandigarh and Puducherry | Expected: they pay cash instead of grain |

**Trust in the numbers.** 12 SQL data-quality checks run after each load (6 hard failures,
6 monitored warnings) and 11 unit tests cover the cleaning rules.

### SQL

[`sql/04_policy_analysis.sql`](sql/04_policy_analysis.sql) answers 11 questions using CTEs,
`LAG` for year-on-year growth, running totals for concentration, `RANK` and `NTILE` within
regions, share-of-total with `SUM() OVER ()`, a moving average, self-joins and `NOT EXISTS`.

### Statistics and machine learning

- Spearman rank correlation and a log-log regression with robust standard errors, controlling for state size.
- A gap analysis: actual inter-state transactions against the level the migrant count predicts.
- K-means clustering on three behaviour indicators, with the number of clusters chosen by silhouette score.

## Run it

```bash
pip install -r requirements.txt
python run_pipeline.py      # raw files -> validated model (SQLite + CSV)
python run_sql.py           # data-quality checks + 11 policy queries
python -m pytest            # 11 unit tests
jupyter notebook notebooks/onorc_analysis.ipynb
```

## Limitations

- **State-level, yearly data.** No district, shop or household detail.
- **26 to 36 observations.** Correlations are indicative and confidence intervals are wide.
- **eShram migrants are registered urban workers only** (about 305,000 people), a small share of all migrants.
- **Reporting changes drive some numbers.** Large jumps and collapses are flagged; smaller ones cannot be seen.
- **Associations, not causes.** The data cannot say why usage is low in a state.

Independent analysis of public data; not affiliated with the Government of India.

## Author

**Kushagra Jha** · Data Analyst · [LinkedIn](https://www.linkedin.com/in/ADD-YOUR-ID)
