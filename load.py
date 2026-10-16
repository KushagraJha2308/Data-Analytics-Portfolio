"""Load: write the star schema to SQLite (for SQL analysis) and CSV (for Power BI)."""
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
        # Create typed tables with keys first, then append, so constraints are enforced.
        conn.executescript((config.SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))
        for name, df in tables.items():
            out = df.copy()
            for col in out.select_dtypes(include=["datetime", "datetimetz"]).columns:
                out[col] = out[col].dt.strftime("%Y-%m-%d")
            out.to_sql(name, conn, if_exists="append", index=False)
            out.to_csv(config.PROCESSED_DIR / f"{name}.csv", index=False, encoding="utf-8-sig")
            log.info("Loaded %-20s %6d rows", name, len(out))
        conn.executescript((config.SQL_DIR / "02_views.sql").read_text(encoding="utf-8"))


def read_sql(query: str) -> pd.DataFrame:
    with sqlite3.connect(config.DB_PATH) as conn:
        return pd.read_sql_query(query, conn)
