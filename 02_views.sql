-- =============================================================================
-- 02_views.sql  |  Reusable view on top of the model
-- =============================================================================

-- State-year facts with the state attributes most queries need.
CREATE VIEW vw_state_year AS
SELECT
    f.state,
    s.state_code,
    s.region,
    s.is_union_territory,
    s.pds_mode,
    s.migration_role,
    s.migrants_in,
    s.migrants_out,
    f.year,
    f.beneficiaries,
    f.portability_txn,
    f.interstate_txn,
    f.intrastate_txn,
    f.interstate_share_pct,
    f.portability_per_100_beneficiaries,
    f.interstate_per_100k_beneficiaries,
    f.distribution_mt,
    f.kg_per_beneficiary_month,
    f.deleted_cards,
    f.deleted_per_1000_beneficiaries,
    f.portability_growth_pct,
    f.is_onboarding_jump,
    f.interstate_exceeds_total
FROM fact_state_year f
JOIN dim_state s ON s.state = f.state;
