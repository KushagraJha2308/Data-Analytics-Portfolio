"""Extract: read the raw data.gov.in files into one long table.

Every source is a small table published as an answer to a question in Parliament.
The layouts differ (column names, a serial-number column, a total row at the bottom),
so each file is reshaped to the same long format:  state_raw | year | metric | value.
"""
import logging
import re

import pandas as pd

from . import config

log = logging.getLogger(__name__)

STATE_COLUMN = re.compile(r"^state\s*/\s*uts?$", re.IGNORECASE)


def read_source(file_name: str) -> pd.DataFrame:
    """Read one raw file and return it with a single, consistently named state column."""
    df = pd.read_csv(config.RAW_DIR / file_name)
    df.columns = [c.strip() for c in df.columns]
    state_cols = [c for c in df.columns if STATE_COLUMN.match(c)]
    if len(state_cols) != 1:
        raise ValueError(f"{file_name}: expected exactly one State/UT column, found {state_cols}")
    return df.rename(columns={state_cols[0]: "state_raw"})


def to_long(df: pd.DataFrame, mapping: dict, file_name: str) -> pd.DataFrame:
    missing = [c for c in mapping if c not in df.columns]
    if missing:
        raise ValueError(f"{file_name}: expected columns not found: {missing}")
    long = df.melt(id_vars="state_raw", value_vars=list(mapping), var_name="raw_column", value_name="value")
    long["value"] = pd.to_numeric(long["value"], errors="coerce")
    long["source_file"] = file_name
    return long


def extract_yearly() -> pd.DataFrame:
    frames = []
    for file_name, mapping in config.YEARLY_SOURCES.items():
        long = to_long(read_source(file_name), mapping, file_name)
        long["year"] = long["raw_column"].map(lambda c: mapping[c][0])
        long["metric"] = long["raw_column"].map(lambda c: mapping[c][1])
        frames.append(long.drop(columns="raw_column"))
        log.info("%-48s %4d values", file_name, len(long))
    return pd.concat(frames, ignore_index=True)


def extract_snapshot() -> pd.DataFrame:
    frames = []
    for file_name, mapping in config.SNAPSHOT_SOURCES.items():
        long = to_long(read_source(file_name), mapping, file_name)
        long["metric"] = long["raw_column"].map(mapping)
        frames.append(long.drop(columns="raw_column"))
        log.info("%-48s %4d values", file_name, len(long))
    return pd.concat(frames, ignore_index=True)


def extract_deleted_cross_checks() -> pd.DataFrame:
    """The two shorter deleted-ration-card series, used only to verify the main one."""
    frames = []
    for file_name in config.DELETED_CARDS_CROSS_CHECK:
        df = read_source(file_name)
        years = {c: (int(c), "deleted_cards") for c in df.columns if c.isdigit()}
        long = to_long(df, years, file_name)
        long["year"] = long["raw_column"].astype(int)
        frames.append(long.drop(columns="raw_column"))
    return pd.concat(frames, ignore_index=True)
