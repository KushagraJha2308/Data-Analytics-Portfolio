-- =============================================================================
-- 01_schema.sql  |  Star schema for Netflix engagement reporting
-- Grain of fact_engagement: one row per title per half-year reporting period.
-- =============================================================================
PRAGMA foreign_keys = ON;

CREATE TABLE dim_period (
    period_id       INTEGER PRIMARY KEY,      -- YYYYH, e.g. 20261 = 2026 H1
    period_label    TEXT    NOT NULL UNIQUE,
    period_start    TEXT    NOT NULL,
    period_end      TEXT    NOT NULL,
    days_in_period  INTEGER NOT NULL,
    period_seq      INTEGER NOT NULL UNIQUE   -- 1, 2, 3 ... for period-over-period joins
);

CREATE TABLE dim_title (
    title_id          INTEGER PRIMARY KEY,
    content_type      TEXT    NOT NULL CHECK (content_type IN ('Show', 'Movie')),
    title             TEXT    NOT NULL,
    release_date      TEXT,                   -- NULL = licensed title (no Netflix premiere date)
    title_english     TEXT    NOT NULL,
    title_native      TEXT,
    series_name       TEXT,                   -- franchise, e.g. 'Bridgerton'
    season_number     INTEGER,
    is_limited_series INTEGER NOT NULL CHECK (is_limited_series IN (0, 1)),
    is_live_event     INTEGER NOT NULL CHECK (is_live_event IN (0, 1)),      -- runtime footnoted 'H:MM*'
    language_group   TEXT    NOT NULL,       -- inferred from the script of the native title
    is_non_english    INTEGER NOT NULL CHECK (is_non_english IN (0, 1)),
    title_origin      TEXT    NOT NULL CHECK (title_origin IN ('Netflix release', 'Licensed / undated')),
    release_year      INTEGER
);

CREATE TABLE dim_date (
    date          TEXT PRIMARY KEY,
    year          INTEGER NOT NULL,
    quarter       TEXT    NOT NULL,
    month_number  INTEGER NOT NULL,
    month_name    TEXT    NOT NULL,
    year_month    TEXT    NOT NULL,
    half_year     TEXT    NOT NULL
);

CREATE TABLE fact_engagement (
    period_id          INTEGER NOT NULL REFERENCES dim_period (period_id),
    title_id           INTEGER NOT NULL REFERENCES dim_title (title_id),
    content_type       TEXT    NOT NULL,
    available_globally INTEGER NOT NULL CHECK (available_globally IN (0, 1)),
    hours_viewed       INTEGER NOT NULL CHECK (hours_viewed > 0),
    views              INTEGER NOT NULL CHECK (views > 0),
    runtime_minutes    REAL,                  -- NULL where Netflix reported '*'
    release_cohort     TEXT    NOT NULL CHECK (release_cohort IN ('New release', 'Netflix catalogue', 'Licensed / undated')),
    days_available     INTEGER NOT NULL,      -- days the title could be watched inside the period
    views_per_day      REAL    NOT NULL,
    netflix_rank       INTEGER NOT NULL,      -- position in the source sheet
    hours_decile       INTEGER NOT NULL CHECK (hours_decile BETWEEN 1 AND 10),  -- 1 = top 10% by hours
    PRIMARY KEY (period_id, title_id)
);

-- Netflix's aggregate line for titles under 50K views (published from 2025 H2).
CREATE TABLE fact_other_viewing (
    period_id     INTEGER NOT NULL REFERENCES dim_period (period_id),
    content_type  TEXT    NOT NULL,
    hours_viewed  INTEGER NOT NULL,
    PRIMARY KEY (period_id, content_type)
);

CREATE INDEX idx_fact_title  ON fact_engagement (title_id);
CREATE INDEX idx_title_series ON dim_title (series_name, season_number);
