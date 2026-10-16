-- =============================================================================
-- 03_data_quality_checks.sql  |  Automated checks run after every load
-- FAIL = the data is wrong and must not be used.  WARN = known and monitored.
-- =============================================================================

-- name: data_quality_checks
SELECT 'duplicate_state_year' AS check_name, 'FAIL' AS severity,
       COUNT(*) AS offending_rows,
       'More than one row for a state in a year' AS note
FROM (SELECT state, year FROM fact_state_year GROUP BY 1, 2 HAVING COUNT(*) > 1)

UNION ALL
SELECT 'fact_without_state', 'FAIL', COUNT(*),
       'Fact rows whose state is missing from dim_state'
FROM fact_state_year f
LEFT JOIN dim_state s ON s.state = f.state
WHERE s.state IS NULL

UNION ALL
SELECT 'published_total_mismatch', 'FAIL', COUNT(*),
       'Sum of state rows differs from the published total by more than 0.01%'
FROM source_reconciliation
WHERE ABS(difference_pct) > 0.01

UNION ALL
SELECT 'beneficiary_split_mismatch', 'FAIL', COUNT(*),
       'AAY + PHH beneficiaries must equal the total'
FROM dim_state
WHERE beneficiaries_2026 IS NOT NULL
  AND ABS(beneficiaries_aay + beneficiaries_phh - beneficiaries_2026) > 0.5

UNION ALL
SELECT 'migrants_in_out_not_balanced', 'FAIL',
       CASE WHEN ABS(SUM(migrants_in) - SUM(migrants_out)) > 0.5 THEN 1 ELSE 0 END,
       'Every migrant counted "in" somewhere is counted "out" somewhere else'
FROM dim_state

UNION ALL
SELECT 'interstate_exceeds_total', 'FAIL', COUNT(*),
       'Inter-state transactions cannot be more than all portability transactions'
FROM fact_state_year
WHERE interstate_exceeds_total = 1

UNION ALL
SELECT 'rounding_gap_in_published_total', 'WARN', COUNT(*),
       'Published totals that differ from the sum of states by 1 to 3 units (rounding at source)'
FROM source_reconciliation
WHERE difference <> 0

UNION ALL
SELECT 'onboarding_jump', 'WARN', COUNT(*),
       'Year-on-year jump of 20x or more: a state joining the system, excluded from growth rates'
FROM fact_state_year
WHERE is_onboarding_jump = 1

UNION ALL
SELECT 'interstate_equals_total', 'WARN', COUNT(*),
       'Inter-state count identical to the total: possible reporting artefact'
FROM fact_state_year
WHERE interstate_txn IS NOT NULL AND interstate_txn = portability_txn

UNION ALL
SELECT 'portability_not_reported', 'WARN', COUNT(*),
       'State-years from 2023 with no portability figure'
FROM fact_state_year
WHERE year >= 2023 AND portability_txn IS NULL

UNION ALL
SELECT 'interstate_not_reported', 'WARN', COUNT(*),
       'State-years from 2024 with a portability figure but no inter-state figure'
FROM fact_state_year
WHERE year >= 2024 AND portability_txn IS NOT NULL AND interstate_txn IS NULL

UNION ALL
SELECT 'collapse_in_reported_transactions', 'WARN', COUNT(*),
       'Transactions fell by more than 95% in a year: likely a reporting gap'
FROM fact_state_year
WHERE portability_growth_pct < -95;
