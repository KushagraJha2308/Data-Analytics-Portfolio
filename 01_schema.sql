-- =============================================================================
-- 01_schema.sql  |  Model for One Nation One Ration Card (ONORC) analysis
-- Grain of fact_state_year: one row per State/UT per calendar year.
-- =============================================================================
PRAGMA foreign_keys = ON;

CREATE TABLE dim_state (
    state                       TEXT PRIMARY KEY,
    state_code                  TEXT NOT NULL UNIQUE,
    region                      TEXT NOT NULL,
    is_union_territory          INTEGER NOT NULL CHECK (is_union_territory IN (0, 1)),
    pds_mode                    TEXT NOT NULL,     -- 'Foodgrain' or 'Cash transfer (DBT)'
    -- snapshot attributes (early 2026); NULL where the source did not list the state
    beneficiaries_2026          REAL,
    beneficiaries_aay           REAL,              -- Antyodaya Anna Yojana: the poorest households
    beneficiaries_phh           REAL,              -- priority households
    eshram_registrations_2025   REAL,
    eshram_registrations_total  REAL,
    migrants_in                 REAL,              -- urban migrant workers registered on eShram, working here
    migrants_out                REAL,              -- urban migrant workers from here, working elsewhere
    transit_loss_mt             REAL,
    transit_moved_mt            REAL,
    net_migrants                REAL,
    migrant_in_share_pct        REAL,
    migrant_out_share_pct       REAL,
    aay_share_pct               REAL,
    transit_loss_pct            REAL,
    migration_role              TEXT NOT NULL      -- Destination / Origin / Balanced / Not reported
);

CREATE TABLE fact_state_year (
    state                              TEXT NOT NULL REFERENCES dim_state (state),
    year                               INTEGER NOT NULL,
    beneficiaries                      REAL,
    deleted_cards                      REAL,
    distribution_mt                    REAL,       -- foodgrain distributed, metric tonnes
    interstate_txn                     REAL,       -- ration drawn in this state by a card from another state
    portability_txn                    REAL,       -- all portability transactions (intra + inter state)
    intrastate_txn                     REAL,
    interstate_share_pct               REAL,
    portability_per_100_beneficiaries  REAL,
    interstate_per_100k_beneficiaries  REAL,
    kg_per_beneficiary_month           REAL,
    deleted_per_1000_beneficiaries     REAL,
    portability_growth_pct             REAL,
    is_onboarding_jump                 INTEGER NOT NULL CHECK (is_onboarding_jump IN (0, 1)),
    interstate_exceeds_total           INTEGER NOT NULL CHECK (interstate_exceeds_total IN (0, 1)),
    PRIMARY KEY (state, year)
);

-- Published "Total" rows compared with the sum of the state rows above them.
CREATE TABLE source_reconciliation (
    source_file      TEXT NOT NULL,
    metric           TEXT NOT NULL,
    year             REAL,
    published_total  REAL NOT NULL,
    sum_of_states    REAL NOT NULL,
    difference       REAL NOT NULL,
    difference_pct   REAL NOT NULL
);
