"""Load: write the tables to SQLite (for SQL analysis) and CSV (for Power BI)."""
import logging
import sqlite3

import pandas as pd

from . import config

log = logging.getLogger(__name__)


def load(tables: dict) -> None:
    config.PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    if config.DB_PATH.exists():
        config.DB_PATH.unlink()
    with sqlite3.connect(config.DB_PATH) as conn:
        conn.executescript((config.SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
        for name, df in tables.items():
            df.to_sql(name, conn, if_exists="append", index=False)
            df.to_csv(config.PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
            log.info("Loaded %-22s %4d rows", name, len(df))
        conn.executescript((config.SQL_DIR / "02_views.sql").read_text(encoding="utf-8"))


def append_table(name: str, df: pd.DataFrame) -> None:
    with sqlite3.connect(config.DB_PATH) as conn:
        df.to_sql(name, conn, if_exists="replace", index=False)
    df.to_csv(config.PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
    log.info("Wrote %-22s %4d rows", name, len(df))


def read_sql(query: str, **kwargs) -> pd.DataFrame:
    with sqlite3.connect(config.DB_PATH) as conn:
        return pd.read_sql_query(query, conn, **kwargs)
