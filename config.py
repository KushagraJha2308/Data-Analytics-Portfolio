"""Central configuration: paths, data range and modelling parameters."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE_DIR = ROOT / "data" / "reference"
RAW_DIR = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
SQL_DIR = ROOT / "sql"
REPORTS_DIR = ROOT / "reports"
FIGURES_DIR = REPORTS_DIR / "figures"
SQL_OUTPUT_DIR = REPORTS_DIR / "sql_outputs"

UNIVERSE_FILE = REFERENCE_DIR / "universe.csv"
RAW_PRICES_FILE = RAW_DIR / "prices_raw.csv"
RAW_INDEX_FILE = RAW_DIR / "nifty50_raw.csv"
DB_PATH = PROCESSED_DIR / "nse_market.db"

# Data range. END_DATE is fixed so that results in the README can be reproduced exactly.
START_DATE = "2016-01-01"
END_DATE = "2026-10-01"
INDEX_TICKER = "^NSEI"          # NIFTY 50

# A daily move larger than this is checked as a possible unadjusted corporate action.
SUSPECT_JUMP = 0.25

# Modelling
HORIZON = 5                     # predict the next 5 trading days (one week)
FIRST_TEST_YEAR = 2021          # walk-forward: train on everything before, test year by year
TOP_K = 10                      # stocks held by the strategy
COST_PER_TRADE = 0.001          # 0.10% of traded value, charged on every buy and every sell
RANDOM_STATE = 42
