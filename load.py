"""Load: write tables to SQLite (for SQL analysis) and CSV (for Power BI)."""
import logging
import sqlite3

import pandas as pd

from . import config

log = logging.getLogger(__name__)


def _prepare(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    for col in out.select_dtypes(include=["datetime", "datetimetz"]).columns:
        out[col] = out[col].dt.strftime("%Y-%m-%d")
    return out


def load(tables: dict) -> None:
    """Rebuild the database from scratch with the given tables."""
    config.PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    if config.DB_PATH.exists():
        config.DB_PATH.unlink()
    with sqlite3.connect(config.DB_PATH) as conn:
        conn.executescript((config.SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
        for name, df in tables.items():
            out = _prepare(df)
            out.to_sql(name, conn, if_exists="append", index=False)
            out.to_csv(config.PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
            log.info("Loaded %-18s %7d rows", name, len(out))
        conn.executescript((config.SQL_DIR / "02_views.sql").read_text(encoding="utf-8"))


def append_table(name: str, df: pd.DataFrame) -> None:
    """Add or replace one table (used by the modelling step for its outputs)."""
    out = _prepare(df)
    with sqlite3.connect(config.DB_PATH) as conn:
        out.to_sql(name, conn, if_exists="replace", index=False)
    out.to_csv(config.PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
    log.info("Wrote %-18s %7d rows", name, len(out))


def read_sql(query: str, **kwargs) -> pd.DataFrame:
    with sqlite3.connect(config.DB_PATH) as conn:
        return pd.read_sql_query(query, conn, **kwargs)
