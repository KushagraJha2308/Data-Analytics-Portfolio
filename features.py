"""Feature engineering: technical indicators and the prediction target.

Every feature on a given date uses only prices up to and including that date.
The target looks forward. Keeping the two apart is what prevents look-ahead bias.
"""
import numpy as np
import pandas as pd

from . import config

# Stock-level features. In the model these are ranked across stocks on each date.
STOCK_FEATURES = [
    "ret_1d", "ret_5d", "ret_20d", "ret_60d", "mom_12_1", "vol_20d", "volume_ratio",
    "rsi_14", "macd_hist", "bb_pos", "dist_52w_high", "dist_52w_low", "trend_50_200",
    "range_10d", "sector_rel_20d",
]
# Market-level features: identical for every stock on a date, describe the regime.
MARKET_FEATURES = ["mkt_ret_20d", "mkt_vol_20d"]
FEATURES = STOCK_FEATURES + MARKET_FEATURES


def rsi(close: pd.Series, window: int = 14) -> pd.Series:
    """Wilder's Relative Strength Index, 0-100."""
    delta = close.diff()
    gain = delta.clip(lower=0).ewm(alpha=1 / window, min_periods=window, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1 / window, min_periods=window, adjust=False).mean()
    return 100 - 100 / (1 + gain / loss)


def _one_stock(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    c = df["adj_close"]
    for n in (5, 20, 60):
        df[f"ret_{n}d"] = c.pct_change(n)
    # 12-month momentum skipping the latest month (the classic momentum definition).
    df["mom_12_1"] = c.shift(21) / c.shift(252) - 1
    df["vol_20d"] = df["ret_1d"].rolling(20).std()
    df["volume_ratio"] = df["volume"] / df["volume"].rolling(20).mean()
    df["rsi_14"] = rsi(c)

    macd = c.ewm(span=12, adjust=False).mean() - c.ewm(span=26, adjust=False).mean()
    df["macd_hist"] = (macd - macd.ewm(span=9, adjust=False).mean()) / c

    sma20, std20 = c.rolling(20).mean(), c.rolling(20).std()
    df["bb_pos"] = (c - sma20) / (2 * std20)                       # position inside Bollinger bands
    df["dist_52w_high"] = c / c.rolling(252).max() - 1
    df["dist_52w_low"] = c / c.rolling(252).min() - 1
    df["trend_50_200"] = c.rolling(50).mean() / c.rolling(200).mean() - 1
    df["range_10d"] = ((df["high"] - df["low"]) / df["close"]).rolling(10).mean()

    # Target: return over the NEXT `HORIZON` trading days.
    df["fwd_ret"] = c.shift(-config.HORIZON) / c - 1
    return df


def build_features(prices: pd.DataFrame, fact_index: pd.DataFrame) -> pd.DataFrame:
    """prices: cleaned daily prices with a `sector` column. Returns one row per symbol-date."""
    parts = [_one_stock(g) for _, g in prices.sort_values(["symbol", "date"]).groupby("symbol")]
    df = pd.concat(parts, ignore_index=True)

    # Relative strength against the stock's own sector on the same day.
    df["sector_rel_20d"] = df["ret_20d"] - df.groupby(["date", "sector"])["ret_20d"].transform("median")

    market = fact_index.sort_values("date").copy()
    market["mkt_ret_20d"] = market["nifty_close"].pct_change(20)
    market["mkt_vol_20d"] = market["nifty_ret_1d"].rolling(20).std()
    df = df.merge(market[["date"] + MARKET_FEATURES], on="date", how="left")

    # Label: did the stock beat the median stock over the next week?
    # A relative target is balanced by construction and removes the market's own direction.
    median_fwd = df.groupby("date")["fwd_ret"].transform("median")
    df["target"] = np.where(df["fwd_ret"].notna(), (df["fwd_ret"] > median_fwd).astype(float), np.nan)

    keep = ["date", "symbol", "sector"] + FEATURES + ["fwd_ret", "target"]
    return df[keep].dropna(subset=FEATURES).reset_index(drop=True)
