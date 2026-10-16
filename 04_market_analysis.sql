-- =============================================================================
-- 04_market_analysis.sql  |  Market questions answered in SQL
-- Each block starts with "-- name:" so run_sql.py can export it to its own CSV.
-- Dialect: SQLite 3.35+. CTEs and window functions are standard SQL.
-- =============================================================================


-- name: q01_universe_by_sector
-- Q1. What does the universe look like? Stocks and liquidity per sector over the last year.
WITH last_year AS (
    SELECT * FROM vw_daily
    WHERE date > (SELECT date(MAX(date), '-1 year') FROM dim_date)
)
SELECT sector,
       COUNT(DISTINCT symbol) AS stocks,
       ROUND(SUM(turnover_cr) / COUNT(DISTINCT date), 0) AS avg_daily_turnover_cr,
       ROUND(100.0 * SUM(turnover_cr) / SUM(SUM(turnover_cr)) OVER (), 1) AS share_of_turnover_pct
FROM last_year
GROUP BY sector
ORDER BY avg_daily_turnover_cr DESC;


-- name: q02_sector_yearly_returns
-- Q2. How did each sector perform each calendar year? (average of its stocks)
WITH year_end AS (
    -- last adjusted close of each stock in each year
    SELECT DISTINCT symbol, sector, year,
           LAST_VALUE(adj_close) OVER (PARTITION BY symbol, year ORDER BY date
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS year_end_close
    FROM vw_daily
),
stock_year AS (
    SELECT symbol, sector, year,
           year_end_close / LAG(year_end_close) OVER (PARTITION BY symbol ORDER BY year) - 1 AS year_return
    FROM year_end
)
SELECT year,
       sector,
       COUNT(*) AS stocks,
       ROUND(100.0 * AVG(year_return), 1) AS avg_return_pct,
       RANK() OVER (PARTITION BY year ORDER BY AVG(year_return) DESC) AS sector_rank
FROM stock_year
WHERE year_return IS NOT NULL
GROUP BY year, sector
ORDER BY year, sector_rank;


-- name: q03_latest_snapshot
-- Q3. Latest trading day per stock with trend and 52-week range.
--     This rebuilds the technical table of the project brief from real prices.
SELECT t.symbol,
       t.sector,
       t.date,
       ROUND(t.close, 2)                                   AS close,
       ROUND(100.0 * t.ret_1d, 2)                          AS change_pct,
       ROUND(100.0 * (t.adj_close / t.high_52w - 1), 1)    AS pct_from_52w_high,
       ROUND(100.0 * (t.adj_close / t.low_52w - 1), 1)     AS pct_above_52w_low,
       ROUND(t.volume / t.avg_volume_20d, 2)               AS volume_vs_20d_avg,
       CASE
           WHEN t.adj_close > t.sma_50 AND t.sma_50 > t.sma_200 THEN 'Uptrend'
           WHEN t.adj_close < t.sma_50 AND t.sma_50 < t.sma_200 THEN 'Downtrend'
           ELSE 'Mixed'
       END AS trend
FROM vw_technical t
JOIN dim_stock s ON s.symbol = t.symbol AND s.last_date = t.date
ORDER BY pct_from_52w_high DESC;


-- name: q04_golden_cross_test
-- Q4. Does the "golden cross" work? When the 50-day average crosses above the 200-day
--     average, is the return over the next 60 trading days better than on a normal day?
WITH signals AS (
    SELECT symbol,
           date,
           adj_close,
           days_of_history,
           sma_50 - sma_200 AS spread,
           LAG(sma_50 - sma_200) OVER (PARTITION BY symbol ORDER BY date) AS prev_spread,
           LEAD(adj_close, 60)   OVER (PARTITION BY symbol ORDER BY date) / adj_close - 1 AS fwd_return_60d
    FROM vw_technical
),
labelled AS (
    SELECT *,
           CASE WHEN spread > 0 AND prev_spread <= 0 THEN 'Golden cross (50d crosses above 200d)'
                WHEN spread < 0 AND prev_spread >= 0 THEN 'Death cross (50d crosses below 200d)'
                ELSE 'All other days'
           END AS signal
    FROM signals
    WHERE days_of_history = 200          -- both averages fully formed
      AND fwd_return_60d IS NOT NULL
)
SELECT signal,
       COUNT(*) AS observations,
       ROUND(100.0 * AVG(fwd_return_60d), 2) AS avg_fwd_60d_return_pct,
       ROUND(100.0 * AVG(CASE WHEN fwd_return_60d > 0 THEN 1.0 ELSE 0 END), 1) AS pct_positive
FROM labelled
GROUP BY signal
ORDER BY avg_fwd_60d_return_pct DESC;


-- name: q05_max_drawdown
-- Q5. What is the worst peak-to-trough fall each stock has suffered, and when?
WITH running AS (
    SELECT symbol, sector, date, adj_close,
           MAX(adj_close) OVER (PARTITION BY symbol ORDER BY date
                                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_peak
    FROM vw_daily
),
drawdowns AS (
    SELECT *,
           adj_close / running_peak - 1 AS drawdown,
           ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY adj_close / running_peak) AS depth_rank
    FROM running
)
SELECT symbol,
       sector,
       date AS trough_date,
       ROUND(100.0 * drawdown, 1) AS max_drawdown_pct
FROM drawdowns
WHERE depth_rank = 1
ORDER BY max_drawdown_pct;


-- name: q06_market_breadth_extremes
-- Q6. Market breadth: on the ten weakest days, what share of stocks fell,
--     and what did the NIFTY 50 do?
WITH breadth AS (
    SELECT date,
           COUNT(*) AS stocks,
           ROUND(100.0 * AVG(CASE WHEN ret_1d < 0 THEN 1.0 ELSE 0 END), 1) AS pct_declining,
           ROUND(100.0 * AVG(ret_1d), 2) AS avg_stock_return_pct
    FROM fact_daily_price
    WHERE ret_1d IS NOT NULL
    GROUP BY date
)
SELECT b.date,
       b.stocks,
       b.pct_declining,
       b.avg_stock_return_pct,
       ROUND(100.0 * i.nifty_ret_1d, 2) AS nifty_return_pct
FROM breadth b
JOIN fact_index i ON i.date = b.date
ORDER BY b.avg_stock_return_pct
LIMIT 10;


-- name: q07_monthly_seasonality
-- Q7. Is there a calendar pattern? Average monthly return of a stock by month of year.
WITH month_end AS (
    SELECT DISTINCT symbol, year_month, month_number, month_name,
           LAST_VALUE(adj_close) OVER (PARTITION BY symbol, year_month ORDER BY date
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS month_end_close
    FROM vw_daily
),
monthly AS (
    SELECT symbol, year_month, month_number, month_name,
           month_end_close / LAG(month_end_close) OVER (PARTITION BY symbol ORDER BY year_month) - 1 AS month_return
    FROM month_end
)
SELECT month_number,
       month_name,
       COUNT(DISTINCT year_month) AS years_observed,
       ROUND(100.0 * AVG(month_return), 2) AS avg_stock_return_pct,
       ROUND(100.0 * AVG(CASE WHEN month_return > 0 THEN 1.0 ELSE 0 END), 1) AS pct_stock_months_positive
FROM monthly
WHERE month_return IS NOT NULL
GROUP BY month_number, month_name
ORDER BY month_number;


-- name: q08_volume_spike_follow_through
-- Q8. After a volume spike (3x the previous 20-day average), what happens the next day?
--     Split by whether the spike day itself was up or down.
WITH base AS (
    SELECT symbol,
           date,
           ret_1d,
           volume,
           AVG(volume) OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) AS prior_avg_volume,
           COUNT(*)    OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) AS prior_days,
           LEAD(ret_1d) OVER (PARTITION BY symbol ORDER BY date) AS next_day_return
    FROM fact_daily_price
)
SELECT CASE WHEN volume >= 3 * prior_avg_volume AND ret_1d > 0 THEN 'Volume spike on an up day'
            WHEN volume >= 3 * prior_avg_volume AND ret_1d <= 0 THEN 'Volume spike on a down day'
            ELSE 'Normal volume'
       END AS day_type,
       COUNT(*) AS observations,
       ROUND(100.0 * AVG(ret_1d), 2)          AS avg_same_day_return_pct,
       ROUND(100.0 * AVG(next_day_return), 3) AS avg_next_day_return_pct,
       ROUND(100.0 * AVG(CASE WHEN next_day_return > 0 THEN 1.0 ELSE 0 END), 1) AS pct_next_day_positive
FROM base
WHERE prior_days = 20
  AND ret_1d IS NOT NULL
  AND next_day_return IS NOT NULL
GROUP BY day_type
ORDER BY observations;


-- name: q09_longest_winning_streaks
-- Q9. Longest run of consecutive up days per stock (a gaps-and-islands problem).
WITH flagged AS (
    SELECT symbol, date, ret_1d,
           CASE WHEN ret_1d > 0 THEN 1 ELSE 0 END AS is_up,
           ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date) AS rn_all,
           ROW_NUMBER() OVER (PARTITION BY symbol, CASE WHEN ret_1d > 0 THEN 1 ELSE 0 END ORDER BY date) AS rn_in_group
    FROM fact_daily_price
    WHERE ret_1d IS NOT NULL
),
streaks AS (
    -- consecutive rows of the same kind share the same (rn_all - rn_in_group)
    SELECT symbol,
           MIN(date) AS streak_start,
           MAX(date) AS streak_end,
           COUNT(*)  AS up_days,
           ROUND(100.0 * (EXP(SUM(LN(1 + ret_1d))) - 1), 1) AS streak_return_pct
    FROM flagged
    WHERE is_up = 1
    GROUP BY symbol, rn_all - rn_in_group
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY up_days DESC, streak_return_pct DESC) AS rk
    FROM streaks
)
SELECT symbol, streak_start, streak_end, up_days, streak_return_pct
FROM ranked
WHERE rk = 1
ORDER BY up_days DESC, streak_return_pct DESC
LIMIT 15;


-- name: q10_one_year_leaders
-- Q10. One-year return of every stock, ranked overall and inside its sector.
WITH one_year AS (
    SELECT symbol, sector, date, adj_close,
           LAG(adj_close, 252) OVER (PARTITION BY symbol ORDER BY date) AS close_1y_ago
    FROM vw_daily
)
SELECT o.symbol,
       o.sector,
       ROUND(100.0 * (o.adj_close / o.close_1y_ago - 1), 1) AS return_1y_pct,
       RANK() OVER (ORDER BY o.adj_close / o.close_1y_ago DESC)                     AS overall_rank,
       RANK() OVER (PARTITION BY o.sector ORDER BY o.adj_close / o.close_1y_ago DESC) AS sector_rank
FROM one_year o
JOIN dim_stock s ON s.symbol = o.symbol AND s.last_date = o.date
WHERE o.close_1y_ago IS NOT NULL
ORDER BY overall_rank;


-- name: q11_beta_to_nifty
-- Q11. How sensitive is each stock to the market? Beta against the NIFTY 50 over three years.
--      beta = covariance(stock, index) / variance(index), written with plain averages.
WITH paired AS (
    SELECT p.symbol, s.sector, p.ret_1d AS r, i.nifty_ret_1d AS m
    FROM fact_daily_price p
    JOIN fact_index i ON i.date = p.date
    JOIN dim_stock s ON s.symbol = p.symbol
    WHERE p.date > (SELECT date(MAX(date), '-3 years') FROM dim_date)
      AND p.ret_1d IS NOT NULL AND i.nifty_ret_1d IS NOT NULL
)
SELECT symbol,
       sector,
       COUNT(*) AS days,
       ROUND((AVG(r * m) - AVG(r) * AVG(m)) / (AVG(m * m) - AVG(m) * AVG(m)), 2) AS beta,
       ROUND(100.0 * AVG(r) * 252, 1) AS annualised_return_pct
FROM paired
GROUP BY symbol, sector
ORDER BY beta DESC;


-- name: q12_model_picks_by_year
-- Q12. How good were the model's weekly top-10 picks, year by year? (out-of-sample only)
--      hit rate = share of picks that beat the median stock over the next week.
WITH ranked AS (
    SELECT model, test_year, date, symbol, target, fwd_ret,
           ROW_NUMBER() OVER (PARTITION BY model, date ORDER BY prob_up DESC) AS pick_rank,
           AVG(fwd_ret) OVER (PARTITION BY model, date) AS universe_avg_return
    FROM fact_predictions
    WHERE target IS NOT NULL
)
SELECT model,
       test_year,
       COUNT(*) AS picks,
       ROUND(100.0 * AVG(target), 1) AS hit_rate_pct,
       ROUND(100.0 * AVG(fwd_ret), 3) AS avg_pick_return_pct,
       ROUND(100.0 * AVG(universe_avg_return), 3) AS avg_universe_return_pct
FROM ranked
WHERE pick_rank <= 10
GROUP BY model, test_year
ORDER BY model, test_year;
