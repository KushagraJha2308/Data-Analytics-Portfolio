"""Transform: clean raw prices and shape the dimensional tables."""
import logging

import numpy as np
import pandas as pd

from . import config

log = logging.getLogger(__name__)

PRICE_COLS = ["open", "high", "low", "close", "adj_close"]


def clean_prices(raw: pd.DataFrame, index: pd.DataFrame, universe: pd.DataFrame) -> pd.DataFrame:
    """Return one validated row per symbol per real trading day."""
    df = raw.merge(universe[["symbol", "yahoo_ticker", "sector"]], on="yahoo_ticker", how="left",
                   validate="many_to_one")
    if df["symbol"].isna().any():
        raise ValueError("Price rows with a ticker that is not in the universe file")

    n_start = len(df)
    df = df.dropna(subset=["close", "adj_close"])
    # The provider emits placeholder rows on market holidays: zero volume, and no index print.
    trading_days = set(index["date"])
    df = df[(df["volume"] > 0) & df["date"].isin(trading_days)]
    df = df.drop_duplicates(["symbol", "date"]).sort_values(["symbol", "date"]).reset_index(drop=True)
    log.info("Removed %d non-trading rows (holidays, zero volume, nulls)", n_start - len(df))
    return df


def back_adjust_corporate_actions(df: pd.DataFrame, actions: pd.DataFrame) -> pd.DataFrame:
    """Remove price breaks from demergers that the provider left unadjusted.

    A demerger hands part of the company to shareholders as a new share, so the
    old share falls sharply without any loss to the investor. Left alone, the
    model would learn from a crash that never happened. All earlier adjusted
    prices are scaled by the size of the break, which makes that day's return zero.
    """
    df = df.copy()
    df["corporate_action"] = 0
    for action in actions.itertuples():
        mask = df["symbol"] == action.symbol
        day = pd.Timestamp(action.date)
        event = df[mask & (df["date"] == day)]
        before = df[mask & (df["date"] < day)]
        if event.empty or before.empty:
            raise ValueError(f"Corporate action not found in prices: {action.symbol} {action.date}")
        factor = event["adj_close"].iloc[0] / before["adj_close"].iloc[-1]
        df.loc[before.index, "adj_close"] *= factor
        df.loc[event.index, "corporate_action"] = 1
        log.info("Back-adjusted %s for %s on %s (factor %.3f)", action.symbol, action.action, action.date, factor)
    return df


def add_returns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    # Returns always use the adjusted close, so splits and dividends are not read as price moves.
    df["ret_1d"] = df.groupby("symbol")["adj_close"].pct_change()
    df["turnover_cr"] = df["close"] * df["volume"] / 1e7        # rupees crore
    return df


def build_dim_stock(df: pd.DataFrame, universe: pd.DataFrame) -> pd.DataFrame:
    span = df.groupby("symbol").agg(first_date=("date", "min"), last_date=("date", "max"),
                                    trading_days=("date", "size")).reset_index()
    dim = universe.merge(span, on="symbol", how="inner")
    dim["ticker_changed"] = (dim["symbol"] + ".NS" != dim["yahoo_ticker"]).astype(int)
    return dim


def build_dim_date(index: pd.DataFrame) -> pd.DataFrame:
    dates = pd.DatetimeIndex(sorted(index["date"].unique()))
    return pd.DataFrame({
        "date": dates, "year": dates.year, "quarter": "Q" + dates.quarter.astype(str),
        "month_number": dates.month, "month_name": dates.strftime("%b"),
        "year_month": dates.strftime("%Y-%m"), "weekday": dates.strftime("%a"),
    })


def build_fact_index(index: pd.DataFrame) -> pd.DataFrame:
    out = index.sort_values("date")[["date", "close"]].rename(columns={"close": "nifty_close"})
    out["nifty_ret_1d"] = out["nifty_close"].pct_change()
    return out.reset_index(drop=True)


def validate(df: pd.DataFrame) -> None:
    """Stop the pipeline if the cleaned prices break basic market rules."""
    assert not df.duplicated(["symbol", "date"]).any(), "Duplicate symbol-date"
    assert (df[PRICE_COLS] > 0).all().all(), "Non-positive price"
    assert (df["high"] >= df["low"]).all(), "High below low"
    tolerance = 1e-6
    assert (df["close"] <= df["high"] * (1 + tolerance)).all(), "Close above high"
    assert (df["close"] >= df["low"] * (1 - tolerance)).all(), "Close below low"
    jumps = df[(df["ret_1d"].abs() > config.SUSPECT_JUMP) & (df["corporate_action"] == 0)]
    log.info("Validation passed: %d rows, %d stocks. %d moves above %.0f%% kept as genuine: %s",
             len(df), df["symbol"].nunique(), len(jumps), config.SUSPECT_JUMP * 100,
             ", ".join(f"{r.symbol} {r.date:%Y-%m-%d} {r.ret_1d:+.0%}" for r in jumps.itertuples()))


def transform(raw: pd.DataFrame, index: pd.DataFrame, universe: pd.DataFrame,
              actions: pd.DataFrame) -> dict:
    prices = clean_prices(raw, index, universe)
    prices = add_returns(back_adjust_corporate_actions(prices, actions))
    validate(prices)

    fact_cols = ["date", "symbol", "open", "high", "low", "close", "adj_close", "volume",
                 "turnover_cr", "ret_1d", "corporate_action"]
    return {
        "dim_stock": build_dim_stock(prices, universe),
        "dim_date": build_dim_date(index),
        "fact_index": build_fact_index(index),
        "fact_daily_price": prices[fact_cols],
        "_prices": prices,          # with sector, for feature engineering (not loaded)
    }
