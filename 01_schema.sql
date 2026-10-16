-- =============================================================================
-- 01_schema.sql  |  Star schema for NSE daily market data
-- Grain of fact_daily_price: one row per stock per trading day.
-- =============================================================================
PRAGMA foreign_keys = ON;

CREATE TABLE dim_stock (
    symbol          TEXT PRIMARY KEY,         -- symbol as given in the project brief
    yahoo_ticker    TEXT NOT NULL UNIQUE,     -- current ticker at the data provider
    sector          TEXT NOT NULL,
    segment_code    TEXT NOT NULL,
    first_date      TEXT NOT NULL,            -- first trading day available (listing date for newer stocks)
    last_date       TEXT NOT NULL,
    trading_days    INTEGER NOT NULL,
    ticker_changed  INTEGER NOT NULL CHECK (ticker_changed IN (0, 1))
);

CREATE TABLE dim_date (
    date          TEXT PRIMARY KEY,           -- trading days only
    year          INTEGER NOT NULL,
    quarter       TEXT NOT NULL,
    month_number  INTEGER NOT NULL,
    month_name    TEXT NOT NULL,
    year_month    TEXT NOT NULL,
    weekday       TEXT NOT NULL
);

CREATE TABLE fact_index (
    date          TEXT PRIMARY KEY REFERENCES dim_date (date),
    nifty_close   REAL NOT NULL,
    nifty_ret_1d  REAL
);

CREATE TABLE fact_daily_price (
    date              TEXT NOT NULL REFERENCES dim_date (date),
    symbol            TEXT NOT NULL REFERENCES dim_stock (symbol),
    open              REAL NOT NULL CHECK (open > 0),
    high              REAL NOT NULL,
    low               REAL NOT NULL,
    close             REAL NOT NULL CHECK (close > 0),
    adj_close         REAL NOT NULL CHECK (adj_close > 0),   -- adjusted for splits, dividends, demergers
    volume            INTEGER NOT NULL CHECK (volume > 0),
    turnover_cr       REAL NOT NULL,                         -- close x volume, rupees crore
    ret_1d            REAL,                                  -- daily return on adj_close; NULL on first day
    corporate_action  INTEGER NOT NULL CHECK (corporate_action IN (0, 1)),
    PRIMARY KEY (symbol, date),
    CHECK (high >= low)
);

-- One row per stock per day: model inputs and the forward-looking target.
CREATE TABLE fact_features (
    date            TEXT NOT NULL,
    symbol          TEXT NOT NULL,
    sector          TEXT NOT NULL,
    ret_1d REAL, ret_5d REAL, ret_20d REAL, ret_60d REAL, mom_12_1 REAL,
    vol_20d REAL, volume_ratio REAL, rsi_14 REAL, macd_hist REAL, bb_pos REAL,
    dist_52w_high REAL, dist_52w_low REAL, trend_50_200 REAL, range_10d REAL,
    sector_rel_20d REAL, mkt_ret_20d REAL, mkt_vol_20d REAL,
    fwd_ret         REAL,                     -- return over the next 5 trading days (NULL for the last 5)
    target          REAL,                     -- 1 if fwd_ret beat the median stock that day
    PRIMARY KEY (symbol, date)
);

CREATE INDEX idx_price_date ON fact_daily_price (date);
