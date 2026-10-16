"""Transform: clean the raw rows, engineer features and shape a star schema.

Outputs
-------
dim_period        one row per half-year report
dim_title         one row per distinct title (conformed across periods)
fact_engagement   one row per title per period
fact_other_viewing  Netflix's aggregate row for titles under 50K views
"""
import logging
import re
import unicodedata

import numpy as np
import pandas as pd

from . import config

log = logging.getLogger(__name__)

OTHER_ROW = re.compile(r"^Other (Shows|Movies)$")
RUNTIME_PATTERN = re.compile(r"^(\d+):(\d{2})\*?$")

# "Bridgerton: Season 4", "Money Heist: Part 2", "Sex Education: Series 3" ...
SEASON_PATTERN = re.compile(
    r"^(?P<series>.+?):\s*(?:Season|Part|Series|Volume|Vol\.|Chapter|Book|Staffel|Temporada)\s*(?P<num>\d+)\b",
    re.IGNORECASE,
)
# "Stranger Things 5": a bare trailing number. Capped at two digits so that years
# ("Royal Rumble 2025") are not mistaken for season numbers.
TRAILING_NUMBER_PATTERN = re.compile(r"^(?P<series>.+?)\s+(?P<num>\d{1,2})$")
LIMITED_PATTERN = re.compile(r"^(?P<series>.+?):\s*Limited Series\s*$", re.IGNORECASE)

# Script of the original-language title -> language group. Order matters: kana is
# checked before Han because Japanese titles mix both.
SCRIPT_RULES = [
    ("Korean", ("HANGUL",)),
    ("Japanese", ("HIRAGANA", "KATAKANA")),
    ("Chinese", ("CJK",)),
    ("Hindi", ("DEVANAGARI",)),
    ("Arabic", ("ARABIC",)),
    ("Thai", ("THAI",)),
    ("Other non-Latin script", ("CYRILLIC", "HEBREW", "TAMIL", "TELUGU", "BENGALI", "GREEK",
                                "KANNADA", "MALAYALAM", "GUJARATI", "GURMUKHI")),
]


# --------------------------------------------------------------------------- #
# Cleaning
# --------------------------------------------------------------------------- #
def runtime_to_minutes(value) -> float:
    """'8:53' -> 533.0, '2:25*' -> 145.0. A bare '*' means runtime is not reported."""
    match = RUNTIME_PATTERN.match(value) if isinstance(value, str) else None
    if not match:
        return np.nan
    return int(match.group(1)) * 60 + int(match.group(2))


def split_report_rows(raw: pd.DataFrame):
    """Separate real title rows from footnotes and Netflix's 'Other' aggregate rows."""
    title = raw["title"].fillna("").str.strip()
    is_other = title.str.match(OTHER_ROW)
    is_footnote = title.str.startswith("*") | (title == "")

    other = raw.loc[is_other, ["period_id", "content_type", "hours_viewed"]].copy()
    other["hours_viewed"] = other["hours_viewed"].astype(float).astype("int64")

    titles = raw.loc[~is_other & ~is_footnote].copy()
    log.info("Dropped %d footnote rows, set aside %d 'Other' aggregate rows",
             int(is_footnote.sum()), int(is_other.sum()))
    return titles, other.reset_index(drop=True)


def clean(titles: pd.DataFrame) -> pd.DataFrame:
    df = titles.copy()
    df["title"] = df["title"].str.replace(r"\s+", " ", regex=True).str.strip()

    unexpected = set(df["available_globally"].unique()) - {"Yes", "No"}
    if unexpected:
        raise ValueError(f"Unexpected 'Available Globally?' values: {unexpected}")
    df["available_globally"] = (df["available_globally"] == "Yes").astype(int)

    df["release_date"] = pd.to_datetime(df["release_date"], errors="coerce")
    df["hours_viewed"] = pd.to_numeric(df["hours_viewed"]).astype("int64")
    df["views"] = pd.to_numeric(df["views"]).astype("int64")
    df["runtime_minutes"] = df["runtime"].map(runtime_to_minutes)
    # Netflix footnotes the runtime of live events (WWE Raw, award shows) as 'H:MM*'.
    df["is_live_event"] = df["runtime"].str.fullmatch(r"\d+:\d{2}\*").fillna(False).astype(int)

    unparsed = df["runtime_minutes"].isna() & (df["runtime"] != "*")
    if unparsed.any():
        raise ValueError(f"Unrecognised runtime values: {df.loc[unparsed, 'runtime'].unique()[:10]}")
    return df.drop(columns="runtime")


def resolve_key_collisions(df: pd.DataFrame) -> pd.DataFrame:
    """Merge rows that share title + release date within one period.

    A handful of distinct works are published under an identical title with no
    release date (e.g. two adaptations of the same manga). Nothing in the report
    tells them apart, so they are combined: hours and views are summed and the
    attributes of the higher-ranked row are kept. Totals still reconcile.
    """
    key = ["period_id", "content_type", "title", "release_date"]
    is_dup = df.duplicated(key, keep=False)
    if not is_dup.any():
        return df

    dups = df[is_dup].sort_values("source_row")
    totals = dups.groupby(key, dropna=False)[["hours_viewed", "views"]].transform("sum")
    merged = dups.assign(hours_viewed=totals["hours_viewed"], views=totals["views"])
    merged = merged.drop_duplicates(key, keep="first")
    log.warning("Merged %d rows sharing a title key into %d", len(dups), len(merged))
    return pd.concat([df[~is_dup], merged]).sort_index()


# --------------------------------------------------------------------------- #
# Feature engineering
# --------------------------------------------------------------------------- #
def detect_language_group(title: str) -> str:
    """Infer the original language from the script of the native title.

    Netflix lists non-English titles as 'English title // Original title'.
    The report has no language column, so the script is the best available signal.
    Latin-script languages (Spanish, French, German ...) cannot be told apart and
    are grouped together.
    """
    scripts = set()
    for ch in title:
        if ch.isalpha():
            scripts.add(unicodedata.name(ch, "").split(" ")[0])
    for language, markers in SCRIPT_RULES:
        if scripts.intersection(markers):
            return language
    if " // " in title:
        return "Other non-English (Latin script)"
    return "English / untagged"


def parse_series(title_english: str, content_type: str):
    """Return (series_name, season_number, is_limited_series) for a show title."""
    if content_type != "Show":
        return (None, np.nan, 0)
    match = SEASON_PATTERN.match(title_english)
    if match:
        return (match.group("series").strip(), float(match.group("num")), 0)
    match = LIMITED_PATTERN.match(title_english)
    if match:
        return (match.group("series").strip(), 1.0, 1)
    match = TRAILING_NUMBER_PATTERN.match(title_english)
    if match:
        return (match.group("series").strip(), float(match.group("num")), 0)
    return (title_english, np.nan, 0)


def add_title_features(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    parts = df["title"].str.split(" // ")
    df["title_english"] = parts.str[0]
    df["title_native"] = np.where(parts.str.len() > 1, parts.str[-1], None)

    df["language_group"] = df["title"].map(detect_language_group)
    df["is_non_english"] = (df["language_group"] != "English / untagged").astype(int)

    series = [parse_series(t, c) for t, c in zip(df["title_english"], df["content_type"])]
    df[["series_name", "season_number", "is_limited_series"]] = pd.DataFrame(series, index=df.index)
    df["is_limited_series"] = df["is_limited_series"].astype(int)

    # Netflix only publishes a premiere date for its own releases; blank = licensed.
    df["title_origin"] = np.where(df["release_date"].notna(), "Netflix release", "Licensed / undated")
    return df


# --------------------------------------------------------------------------- #
# Star schema
# --------------------------------------------------------------------------- #
def build_dim_period() -> pd.DataFrame:
    dim = pd.DataFrame(config.PERIODS).drop(columns="source_file")
    start, end = pd.to_datetime(dim["period_start"]), pd.to_datetime(dim["period_end"])
    dim["days_in_period"] = (end - start).dt.days + 1
    dim["period_seq"] = range(1, len(dim) + 1)
    return dim


def build_dim_title(df: pd.DataFrame) -> pd.DataFrame:
    # Title text alone is not unique ("Maria" 2019 vs "Maria" 2024), so the
    # natural key is content type + title + release date.
    key = ["content_type", "title", "release_date"]
    attrs = ["title_english", "title_native", "series_name", "season_number",
             "is_limited_series", "is_live_event", "language_group", "is_non_english",
             "title_origin"]
    dim = (df.sort_values("period_id")
             .drop_duplicates(key, keep="last")[key + attrs]
             .sort_values(key, na_position="last")
             .reset_index(drop=True))
    dim.insert(0, "title_id", dim.index + 1)
    dim["release_year"] = dim["release_date"].dt.year.astype("Int64")
    dim["season_number"] = dim["season_number"].astype("Int64")
    return dim


def build_fact(df: pd.DataFrame, dim_title: pd.DataFrame, dim_period: pd.DataFrame) -> pd.DataFrame:
    key = ["content_type", "title", "release_date"]
    fact = df.merge(dim_title[["title_id"] + key], on=key, how="left", validate="many_to_one")
    fact = fact.merge(dim_period[["period_id", "period_start", "period_end", "days_in_period"]],
                      on="period_id", how="left")

    start, end = pd.to_datetime(fact["period_start"]), pd.to_datetime(fact["period_end"])
    released_in_period = fact["release_date"].between(start, end)
    fact["release_cohort"] = np.select(
        [released_in_period, fact["release_date"].notna()],
        ["New release", "Netflix catalogue"],
        default="Licensed / undated",
    )
    # A title launched in June had far fewer days to collect views than one launched
    # in January. days_available lets us compare them on a per-day basis.
    fact["days_available"] = np.where(
        released_in_period, (end - fact["release_date"]).dt.days + 1, fact["days_in_period"]
    ).astype(int)
    fact["views_per_day"] = (fact["views"] / fact["days_available"]).round(1)
    fact["netflix_rank"] = fact["source_row"]
    # 1 = the top 10% of titles by hours within the period and content type.
    pct_rank = fact.groupby(["period_id", "content_type"])["hours_viewed"].rank(
        method="first", ascending=False, pct=True)
    fact["hours_decile"] = np.ceil(pct_rank * 10).astype(int)

    columns = ["period_id", "title_id", "content_type", "available_globally", "hours_viewed",
               "views", "runtime_minutes", "release_cohort", "days_available", "views_per_day",
               "netflix_rank", "hours_decile"]
    return fact[columns].sort_values(["period_id", "content_type", "netflix_rank"]).reset_index(drop=True)


def build_dim_date(dim_title: pd.DataFrame, dim_period: pd.DataFrame) -> pd.DataFrame:
    """Calendar table for the Power BI model (release-date slicing)."""
    start = dim_title["release_date"].min().replace(month=1, day=1)
    end = pd.to_datetime(dim_period["period_end"]).max()
    dates = pd.date_range(start, end, freq="D")
    return pd.DataFrame({
        "date": dates,
        "year": dates.year,
        "quarter": "Q" + dates.quarter.astype(str),
        "month_number": dates.month,
        "month_name": dates.strftime("%b"),
        "year_month": dates.strftime("%Y-%m"),
        "half_year": dates.year.astype(str) + " H" + np.where(dates.month <= 6, "1", "2"),
    })


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
def validate(raw: pd.DataFrame, fact: pd.DataFrame, other: pd.DataFrame, dim_title: pd.DataFrame) -> None:
    """Fail the pipeline if the model no longer reconciles to the source files."""
    assert not fact.duplicated(["period_id", "title_id"]).any(), "Duplicate title within a period"
    assert fact["title_id"].notna().all(), "Fact row without a title_id"
    assert dim_title["title_id"].is_unique, "dim_title key is not unique"
    assert (fact["hours_viewed"] > 0).all() and (fact["views"] > 0).all(), "Non-positive engagement"

    raw_hours = pd.to_numeric(raw["hours_viewed"], errors="coerce").sum()
    model_hours = fact["hours_viewed"].sum() + other["hours_viewed"].sum()
    assert raw_hours == model_hours, f"Hours do not reconcile: raw={raw_hours:,} model={model_hours:,}"
    log.info("Validation passed: %d fact rows, %d titles, %.1fB hours reconciled to source",
             len(fact), len(dim_title), model_hours / 1e9)


def transform(raw: pd.DataFrame) -> dict:
    titles, other = split_report_rows(raw)
    enriched = add_title_features(resolve_key_collisions(clean(titles)))

    dim_period = build_dim_period()
    dim_title = build_dim_title(enriched)
    fact = build_fact(enriched, dim_title, dim_period)
    validate(raw, fact, other, dim_title)

    return {
        "dim_period": dim_period,
        "dim_title": dim_title,
        "dim_date": build_dim_date(dim_title, dim_period),
        "fact_engagement": fact,
        "fact_other_viewing": other,
    }
