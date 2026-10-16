"""Extract: read the raw Netflix engagement workbooks into one long DataFrame.

The workbooks are formatted for humans, not machines: a banner above the header,
an empty first column, a footnote at the bottom and (from 2025 H2) an aggregate
"Other Shows" / "Other Movies" row. Everything is read as text so that no value
is silently coerced before the transform step has validated it.
"""
import logging

import pandas as pd

from . import config

log = logging.getLogger(__name__)

HEADER_SEARCH_ROWS = 20


def _parse_sheet(raw: pd.DataFrame, source: str) -> pd.DataFrame:
    # Locate the header row instead of hard-coding it, so a layout change fails loudly.
    is_header = (raw.head(HEADER_SEARCH_ROWS) == "Title").any(axis=1)
    if not is_header.any():
        raise ValueError(f"No 'Title' header found in {source}")
    header_idx = is_header.idxmax()

    body = raw.iloc[header_idx + 1 :].dropna(axis=1, how="all")
    if body.shape[1] != len(config.RAW_COLUMNS):
        raise ValueError(
            f"Expected {len(config.RAW_COLUMNS)} columns in {source}, found {body.shape[1]}"
        )
    body.columns = config.RAW_COLUMNS
    return body.dropna(how="all").reset_index(drop=True)


def extract_all() -> pd.DataFrame:
    """Return every row of every report, tagged with period and content type."""
    frames = []
    for period in config.PERIODS:
        path = config.RAW_DIR / period["source_file"]
        # One read per workbook: opening an .xlsx is the slow part.
        sheets = pd.read_excel(path, sheet_name=list(config.SHEETS), header=None, dtype=str)
        for sheet_name, content_type in config.SHEETS.items():
            df = _parse_sheet(sheets[sheet_name], f"{path.name} / {sheet_name}")
            df["period_id"] = period["period_id"]
            df["content_type"] = content_type
            # Row order in the source is Netflix's own ranking by views.
            df["source_row"] = df.index + 1
            frames.append(df)
            log.info("%s | %-6s | %5d rows", period["period_label"], sheet_name, len(df))
    return pd.concat(frames, ignore_index=True)
