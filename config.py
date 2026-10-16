"""Central configuration: paths and the specification of every source file."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
REFERENCE_DIR = ROOT / "data" / "reference"
PROCESSED_DIR = ROOT / "data" / "processed"
SQL_DIR = ROOT / "sql"
REPORTS_DIR = ROOT / "reports"
FIGURES_DIR = REPORTS_DIR / "figures"
SQL_OUTPUT_DIR = REPORTS_DIR / "sql_outputs"
DB_PATH = PROCESSED_DIR / "onorc.db"

# Yearly sources: one row per State/UT, one column per year (or per year and measure).
# "columns" maps a column in the raw file to (year, metric).
YEARLY_SOURCES = {
    "portability_transactions_2023_2025.csv": {
        "2023": (2023, "portability_txn"), "2024": (2024, "portability_txn"), "2025": (2025, "portability_txn")},
    "interstate_portability_2024_2025.csv": {
        "2024": (2024, "interstate_txn"), "2025": (2025, "interstate_txn")},
    "nfsa_beneficiaries_distribution_2023_2025.csv": {
        "2023 - Beneficiaries count": (2023, "beneficiaries"), "2023 - Distribution (MT)": (2023, "distribution_mt"),
        "2024 - Beneficiaries count": (2024, "beneficiaries"), "2024 - Distribution (MT)": (2024, "distribution_mt"),
        "2025 - Beneficiaries count": (2025, "beneficiaries"), "2025 - Distribution (MT)": (2025, "distribution_mt")},
    "deleted_ration_cards_2020_2025.csv": {str(y): (y, "deleted_cards") for y in range(2020, 2026)},
}

# Three separate parliamentary answers report deleted ration cards. The longest series is
# loaded; the other two are used only to cross-check it.
DELETED_CARDS_CROSS_CHECK = ["deleted_ration_cards_2021_2025.csv", "deleted_ration_cards_2023_2025.csv"]

# Snapshot sources: one value per State/UT at a point in time. Maps raw column -> metric.
SNAPSHOT_SOURCES = {
    "nfsa_beneficiaries_2026.csv": {
        "Beneficiary Count - AAY": "beneficiaries_aay", "Beneficiary Count - PHH": "beneficiaries_phh",
        "Beneficiary Count - Total": "beneficiaries_2026"},
    "eshram_urban_migrants_2026.csv": {"Migrant in": "migrants_in", "Migrant out": "migrants_out"},
    "eshram_unorganised_workers_2025_2026.csv": {
        "Registration for the year 2025": "eshram_registrations_2025",
        "Registration till date as on 29-01-2026": "eshram_registrations_total"},
    "nfsa_transit_losses_2025.csv": {
        "Wheat + Rice - Quantity Moved": "transit_moved_mt", "Wheat + Rice - Quantity Loss": "transit_loss_mt"},
}

# A year-on-year jump above this multiple is treated as a system onboarding event,
# not as real growth in usage.
ONBOARDING_MULTIPLE = 20
RANDOM_STATE = 42
