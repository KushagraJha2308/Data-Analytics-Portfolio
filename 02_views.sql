-- =============================================================================
-- 02_views.sql  |  Reusable views on top of the star schema
-- =============================================================================

-- Daily prices with stock attributes and calendar fields: the start of most queries.
CREATE VIEW vw_daily AS
SELECT
    p.date,
    d.year,
    d.month_number,
    d.month_name,
    d.year_month,
    p.symbol,
    s.sector,
    p.open, p.high, p.low, p.close, p.adj_close,
    p.volume,
    p.turnover_cr,
    p.ret_1d,
    p.corporate_action
FROM fact_daily_price p
JOIN dim_stock s ON s.symbol = p.symbol
JOIN dim_date  d ON d.date   = p.date;

-- Moving averages and 52-week range per stock, computed with window frames.
-- 252 trading days is about one year.
CREATE VIEW vw_technical AS
SELECT
    date,
    symbol,
    sector,
    close,
    adj_close,
    volume,
    ret_1d,
    COUNT(*)        OVER w200 AS days_of_history,
    AVG(adj_close)  OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW)  AS sma_50,
    AVG(adj_close)  OVER w200 AS sma_200,
    AVG(volume)     OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)  AS avg_volume_20d,
    MAX(adj_close)  OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 251 PRECEDING AND CURRENT ROW) AS high_52w,
    MIN(adj_close)  OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN 251 PRECEDING AND CURRENT ROW) AS low_52w
FROM vw_daily
WINDOW w200 AS (PARTITION BY symbol ORDER BY date ROWS BETWEEN 199 PRECEDING AND CURRENT ROW);
