"""Central configuration: paths, reporting periods and source files."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
SQL_DIR = ROOT / "sql"
REPORTS_DIR = ROOT / "reports"
FIGURES_DIR = REPORTS_DIR / "figures"
SQL_OUTPUT_DIR = REPORTS_DIR / "sql_outputs"
DB_PATH = PROCESSED_DIR / "netflix_engagement.db"

# Netflix publishes one engagement report per half-year.
# period_id is a sortable integer (YYYYH) so that "previous period" is a simple LAG.
PERIODS = [
    {
        "period_id": 20251,
        "period_label": "2025 H1",
        "period_start": "2025-01-01",
        "period_end": "2025-06-30",
        "source_file": "netflix_what_we_watched_2025_h1.xlsx",
    },
    {
        "period_id": 20252,
        "period_label": "2025 H2",
        "period_start": "2025-07-01",
        "period_end": "2025-12-31",
        "source_file": "netflix_what_we_watched_2025_h2.xlsx",
    },
    {
        "period_id": 20261,
        "period_label": "2026 H1",
        "period_start": "2026-01-01",
        "period_end": "2026-06-30",
        "source_file": "netflix_what_we_watched_2026_h1.xlsx",
    },
]

SHEETS = {"Shows": "Show", "Movies": "Movie"}
RAW_COLUMNS = ["title", "available_globally", "release_date", "hours_viewed", "runtime", "views"]
