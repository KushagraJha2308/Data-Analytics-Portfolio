"""Extract: download daily prices for the stock universe and cache them as raw CSV.

The raw files are the single source for everything downstream. They are only
re-downloaded when asked (run_pipeline.py --refresh), so the analysis is
reproducible even though the data provider revises history over time.
"""
import logging

import pandas as pd

from . import config

log = logging.getLogger(__name__)

PRICE_COLUMNS = {"Open": "open", "High": "high", "Low": "low", "Close": "close",
                 "Adj Close": "adj_close", "Volume": "volume"}


def load_universe() -> pd.DataFrame:
    return pd.read_csv(config.UNIVERSE_FILE)


def _download(tickers: list) -> pd.DataFrame:
    import yfinance as yf          # imported here so the rest of the project runs offline

    end = pd.Timestamp(config.END_DATE) + pd.Timedelta(days=1)      # yfinance end is exclusive
    wide = yf.download(tickers, start=config.START_DATE, end=end.strftime("%Y-%m-%d"),
                       auto_adjust=False, progress=False, group_by="ticker", threads=False)
    frames = []
    for ticker in tickers:
        df = wide[ticker].rename(columns=PRICE_COLUMNS)[list(PRICE_COLUMNS.values())]
        df = df.dropna(how="all").reset_index().rename(columns={"Date": "date"})
        df.insert(1, "yahoo_ticker", ticker)
        frames.append(df)
        if df.empty:
            log.warning("No data returned for %s", ticker)
    return pd.concat(frames, ignore_index=True)


def extract(refresh: bool = False) -> tuple:
    """Return (stock prices, index prices) in long format, downloading if needed."""
    config.RAW_DIR.mkdir(parents=True, exist_ok=True)
    if refresh or not config.RAW_PRICES_FILE.exists():
        universe = load_universe()
        log.info("Downloading %d stocks and the index, %s to %s",
                 len(universe), config.START_DATE, config.END_DATE)
        _download(universe["yahoo_ticker"].tolist()).to_csv(config.RAW_PRICES_FILE, index=False)
        _download([config.INDEX_TICKER]).to_csv(config.RAW_INDEX_FILE, index=False)

    prices = pd.read_csv(config.RAW_PRICES_FILE, parse_dates=["date"])
    index = pd.read_csv(config.RAW_INDEX_FILE, parse_dates=["date"])
    log.info("Raw data: %d stock rows, %d index rows", len(prices), len(index))
    return prices, index
