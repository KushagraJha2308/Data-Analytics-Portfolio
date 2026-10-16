-- =============================================================================
-- 03_data_quality_checks.sql  |  Automated checks run after every load
-- FAIL = the data is wrong and must not be used.  WARN = known and monitored.
-- =============================================================================

-- name: data_quality_checks
SELECT 'duplicate_symbol_date' AS check_name, 'FAIL' AS severity,
       COUNT(*) AS offending_rows,
       'More than one price row for a stock on a day' AS note
FROM (SELECT symbol, date FROM fact_daily_price GROUP BY 1, 2 HAVING COUNT(*) > 1)

UNION ALL
SELECT 'price_without_stock', 'FAIL', COUNT(*),
       'Price rows whose symbol is missing from dim_stock'
FROM fact_daily_price p
LEFT JOIN dim_stock s ON s.symbol = p.symbol
WHERE s.symbol IS NULL

UNION ALL
SELECT 'price_on_non_trading_day', 'FAIL', COUNT(*),
       'Price rows on a date the index did not trade'
FROM fact_daily_price p
LEFT JOIN dim_date d ON d.date = p.date
WHERE d.date IS NULL

UNION ALL
SELECT 'close_outside_high_low', 'FAIL', COUNT(*),
       'Close must lie between the day low and the day high'
FROM fact_daily_price
WHERE close > high * 1.000001 OR close < low * 0.999999

UNION ALL
SELECT 'return_missing_after_first_day', 'FAIL', COUNT(*),
       'ret_1d may only be NULL on a stock''s first trading day'
FROM fact_daily_price p
JOIN dim_stock s ON s.symbol = p.symbol
WHERE p.ret_1d IS NULL AND p.date > s.first_date

UNION ALL
SELECT 'feature_row_without_price', 'FAIL', COUNT(*),
       'Every feature row must come from a price row'
FROM fact_features f
LEFT JOIN fact_daily_price p ON p.symbol = f.symbol AND p.date = f.date
WHERE p.symbol IS NULL

UNION ALL
SELECT 'target_not_balanced', 'FAIL',
       CASE WHEN ABS(AVG(target) - 0.5) > 0.02 THEN 1 ELSE 0 END,
       'Target is "beat the median stock", so about half the rows must be 1'
FROM fact_features
WHERE target IS NOT NULL

UNION ALL
SELECT 'stocks_listed_after_start', 'WARN', COUNT(*),
       'Stocks with a shorter history than the index (newer listings)'
FROM dim_stock
WHERE first_date > (SELECT MIN(date) FROM dim_date)

UNION ALL
SELECT 'stock_days_missing_vs_index', 'WARN',
       COALESCE(SUM(expected.days - s.trading_days), 0),
       'Trading days between first and last date with no price row (halts, provider gaps)'
FROM dim_stock s
JOIN (SELECT s2.symbol, COUNT(*) AS days
      FROM dim_stock s2
      JOIN dim_date d ON d.date BETWEEN s2.first_date AND s2.last_date
      GROUP BY s2.symbol) expected ON expected.symbol = s.symbol

UNION ALL
SELECT 'ticker_changed_since_brief', 'WARN', COUNT(*),
       'Symbols in the brief that now trade under a different ticker'
FROM dim_stock
WHERE ticker_changed = 1

UNION ALL
SELECT 'corporate_action_back_adjusted', 'WARN', COUNT(*),
       'Demerger price breaks removed by back-adjustment'
FROM fact_daily_price
WHERE corporate_action = 1

UNION ALL
SELECT 'daily_move_above_25pct', 'WARN', COUNT(*),
       'Large genuine moves kept in the data (COVID crash, bank recapitalisation, Vodafone Idea)'
FROM fact_daily_price
WHERE ABS(ret_1d) > 0.25

UNION ALL
SELECT 'target_not_yet_known', 'WARN', COUNT(*),
       'Latest feature rows whose 5-day forward return has not happened yet'
FROM fact_features
WHERE target IS NULL;
