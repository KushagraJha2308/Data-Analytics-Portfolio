# Can machine learning pick NSE stocks? An honest test

Ten years of daily prices for 54 large NSE stocks (139,039 rows), a SQL star schema, three
machine-learning models with walk-forward validation, and a backtest with trading costs.

**Stack:** Python (pandas, scikit-learn, SciPy) · SQL (SQLite, window functions) · Machine learning (classification, clustering) · Power BI (DAX)

## The question

Using only price and volume history, can a model predict which stocks will beat the median
stock over the next week, and does that survive trading costs?

Most stock-prediction tutorials report 80–95% accuracy. This project shows where those
numbers come from, removes the error, and reports what is left.

## Key findings

| # | Finding | Evidence |
|---|---|---|
| 1 | **The validation method matters more than the model.** The same model scores an AUC of 0.74 with a shuffled train/test split and 0.50 with a time-ordered split. | Leakage experiment, same data and model |
| 2 | **There is a small edge, and it is not statistically significant.** Out-of-sample AUC is 0.51 for all three models over 2021–2026. | Walk-forward validation, 75,099 predictions |
| 3 | **Before costs the strategy wins; after costs it does not.** 28.4% a year before costs vs 22.2% for the benchmark; 20.9% after costs. | Weekly top-10 backtest, 283 weeks |
| 4 | **The edge is probably real but too small to trade weekly.** The model beats 96% of 1,000 random portfolios, but breaks even only if a trade costs under 0.08%. | Random-portfolio test, cost sensitivity |
| 5 | **Simple models are enough.** Logistic regression (AUC 0.508) is almost as good as gradient boosting (0.510). | Model comparison |
| 6 | **Momentum and trend carry the signal.** RSI, MACD and Bollinger bands add almost nothing out of sample. | Permutation importance on 2025–26 data |
| 7 | **Sectors are only partly real.** Same-sector stocks correlate 0.49 vs 0.25 across sectors; Energy, Metals and Defense trade as one cyclical block. | Hierarchical clustering, adjusted Rand index 0.40 |
| 8 | **The "golden cross" does not work here.** 60-day return after a golden cross is 4.96%, against 5.12% on an average day. | SQL query q04, 334 signals |

<p>
  <img src="reports/figures/03_leakage_demo.png" width="49%">
  <img src="reports/figures/05_equity_curve.png" width="49%">
</p>
<p>
  <img src="reports/figures/06_luck_and_costs.png" width="98%">
</p>

Full analysis: [`notebooks/nse_ml_analysis.ipynb`](notebooks/nse_ml_analysis.ipynb)

## Why a negative result is the result

A model that "predicts stocks with 90% accuracy" is a bug, not a finding. The value of this
project is the method: time-ordered validation, a purge gap between train and test, a
balanced relative target, a fair benchmark, trading costs, a luck test, and no tuning on the
test years. The conclusion a business can use: **turnover, not prediction, is the binding
problem.** A slower strategy or non-price data is the next step, not a bigger model.

## How it works

```
project brief ──► universe (54 stocks) ──► download ──► clean ──► features ──► star schema ──► SQL analysis
 (2-day sample)    + ticker mapping        10 years     validate   17 signals   SQLite + CSV └► ML: walk-forward ► backtest
```

**About the data.** The brief was a two-day sample table for these stocks. Two days cannot
train a model, and one of the two (2 October) is a market holiday, so the brief was used as
the specification and filled with real price history from Yahoo Finance.

### Data cleaning

| Issue | Treatment |
|---|---|
| 3 tickers in the brief no longer exist (TATAMOTORS, ZOMATO, LTIM) | Mapping table: brief symbol → current ticker |
| 653 placeholder rows on market holidays | Removed; the NIFTY 50 calendar defines a trading day |
| 2 demergers left unadjusted by the provider (fake crashes of -40% and -65%) | Earlier prices back-adjusted, logged in `corporate_actions.csv` |
| 4 stocks listed after 2016 | Kept from their real listing date, never back-filled |
| 18 genuine moves above 25% (COVID crash, bank recapitalisation) | Kept: they happened |
| Splits and dividends | All returns use the adjusted close |

**Trust in the numbers.** 13 SQL data-quality checks run after each load (7 hard failures,
6 monitored warnings). 8 unit tests cover the rules the results depend on, including a test
that changing future prices cannot change any feature today (no look-ahead), and a test that
the walk-forward split never trains on the future.

### SQL

[`sql/04_market_analysis.sql`](sql/04_market_analysis.sql) answers 12 questions: sector
returns by year, drawdowns, market breadth, seasonality, volume spikes, winning streaks,
beta, and the model's hit rate by year. Techniques: CTEs, window frames for moving averages
and 52-week ranges, `LAG` / `LEAD`, `LAST_VALUE`, running maximum for drawdown,
gaps-and-islands for streaks, and beta computed from plain averages.

### Machine learning

- **Target:** will the stock beat the median stock over the next 5 trading days? Balanced by
  construction, and independent of market direction.
- **Features:** 17 signals (momentum, volatility, volume, RSI, MACD, Bollinger position,
  52-week range, trend, sector-relative strength, market regime), ranked across stocks each day.
- **Models:** logistic regression, random forest, gradient boosting.
- **Validation:** walk-forward by year from 2021, 5-day purge gap, hyperparameters fixed in advance.
- **Unsupervised:** hierarchical clustering on return correlations, compared with sectors.

## Run it

```bash
pip install -r requirements.txt
python run_pipeline.py      # raw prices -> clean star schema + features (uses cached raw data)
python run_model.py         # walk-forward training and backtest (about 10 minutes)
python run_sql.py           # data-quality checks + 12 market queries
python -m pytest            # 8 unit tests
jupyter notebook notebooks/nse_ml_analysis.ipynb
```

### Power BI

Open [`powerbi/NseStockML.pbip`](powerbi/NseStockML.pbip) in Power BI Desktop. Four pages:
Market, Risk and signals, AI model, Strategy backtest. The model pages show the leakage
comparison, AUC by year for the three models, feature importance, the backtest growth curve,
cost sensitivity and the model's latest ranking. Run `python run_dashboard_data.py` to
rebuild the result tables it reads. Details: [`powerbi/DASHBOARD_GUIDE.md`](powerbi/DASHBOARD_GUIDE.md).

A PDF version of the same four pages, built from the same tables by `run_dashboard_pdf.py`:
[`reports/NSE_Stock_ML_Dashboard.pdf`](reports/NSE_Stock_ML_Dashboard.pdf)

<p>
  <img src="reports/dashboard_pages/3_ai_model.png" width="49%">
  <img src="reports/dashboard_pages/4_strategy_backtest.png" width="49%">
</p>

## Limitations

- **Survivorship bias.** The 54 stocks are today's large companies. Firms that shrank or
  were delisted are missing, so every return here, strategy and benchmark, is higher than
  an investor could have earned.
- **One free data provider.** Two corporate actions needed manual correction; others may remain.
- **Flat cost assumption** of 0.10% per trade; real costs depend on order size and liquidity.
- **Sensitive to the rebalance day.** Shifting the weekly schedule by one day changes annual
  returns by about a percentage point.
- This is an analysis project, not investment advice.

## Data not included in this repository

Daily prices come from Yahoo Finance, whose terms do not allow the data to be republished, so the raw prices and the large derived tables are not committed. Rebuild them locally:

```bash
python run_pipeline.py --refresh   # downloads prices for 2016-01-01 to 2026-10-01
python run_model.py
python run_sql.py
python run_dashboard_data.py
```

The provider revises history from time to time, so a fresh download can differ slightly from the numbers in this README. The result tables in `reports/` are the ones the analysis reports.

## Author

**Kushagra Jha** · Data Analyst · [LinkedIn](https://www.linkedin.com/in/ADD-YOUR-ID)
