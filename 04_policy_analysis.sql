-- =============================================================================
-- 04_policy_analysis.sql  |  Policy questions answered in SQL
-- Each block starts with "-- name:" so run_sql.py can export it to its own CSV.
-- Dialect: SQLite 3.35+. CTEs and window functions are standard SQL.
-- =============================================================================


-- name: q01_national_trend
-- Q1. How fast is ration portability growing nationally?
WITH yearly AS (
    SELECT year,
           SUM(portability_txn) AS portability_txn,
           SUM(interstate_txn)  AS interstate_txn,
           SUM(beneficiaries)   AS beneficiaries
    FROM fact_state_year
    WHERE year >= 2023
    GROUP BY year
)
SELECT year,
       ROUND(portability_txn / 1e6, 1) AS portability_txn_mn,
       ROUND(interstate_txn / 1e6, 2)  AS interstate_txn_mn,
       ROUND(100.0 * interstate_txn / portability_txn, 2) AS interstate_share_pct,
       ROUND(100.0 * portability_txn / beneficiaries, 1)  AS txn_per_100_beneficiaries,
       ROUND(100.0 * (portability_txn - LAG(portability_txn) OVER w) / LAG(portability_txn) OVER w, 1) AS portability_growth_pct,
       ROUND(100.0 * (interstate_txn - LAG(interstate_txn) OVER w) / LAG(interstate_txn) OVER w, 1)    AS interstate_growth_pct
FROM yearly
WINDOW w AS (ORDER BY year)
ORDER BY year;


-- name: q02_like_for_like_growth
-- Q2. How much of the growth is real? Growth excluding states that joined the reporting
--     system during the period (a jump of 20x or more in one year).
WITH onboarded AS (
    SELECT DISTINCT state FROM fact_state_year WHERE is_onboarding_jump = 1
),
split AS (
    SELECT f.year,
           CASE WHEN o.state IS NULL THEN 'Reporting since 2023' ELSE 'Joined during 2023-25' END AS state_group,
           SUM(f.portability_txn) AS txn
    FROM fact_state_year f
    LEFT JOIN onboarded o ON o.state = f.state
    WHERE f.year IN (2023, 2025)
    GROUP BY f.year, state_group
)
SELECT state_group,
       ROUND(SUM(CASE WHEN year = 2023 THEN txn END) / 1e6, 1) AS txn_2023_mn,
       ROUND(SUM(CASE WHEN year = 2025 THEN txn END) / 1e6, 1) AS txn_2025_mn,
       ROUND(100.0 * (SUM(CASE WHEN year = 2025 THEN txn END) - SUM(CASE WHEN year = 2023 THEN txn END))
             / SUM(CASE WHEN year = 2023 THEN txn END), 1) AS growth_pct
FROM split
GROUP BY state_group
ORDER BY state_group DESC;


-- name: q03_state_concentration
-- Q3. How concentrated is portability? Running share of transactions, largest states first.
WITH ranked AS (
    SELECT state,
           portability_txn,
           ROW_NUMBER() OVER (ORDER BY portability_txn DESC) AS state_rank,
           100.0 * portability_txn / SUM(portability_txn) OVER () AS share_pct,
           100.0 * SUM(portability_txn) OVER (ORDER BY portability_txn DESC
                                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(portability_txn) OVER () AS cumulative_share_pct
    FROM fact_state_year
    WHERE year = 2025 AND portability_txn IS NOT NULL
)
SELECT state_rank, state,
       ROUND(portability_txn / 1e6, 2) AS portability_txn_mn,
       ROUND(share_pct, 1)             AS share_pct,
       ROUND(cumulative_share_pct, 1)  AS cumulative_share_pct
FROM ranked
WHERE state_rank <= 12
ORDER BY state_rank;


-- name: q04_usage_intensity
-- Q4. Where is portability used most relative to the number of beneficiaries?
--     Ranked nationally and inside each region.
SELECT state,
       region,
       ROUND(portability_per_100_beneficiaries, 1) AS txn_per_100_beneficiaries,
       RANK() OVER (ORDER BY portability_per_100_beneficiaries DESC)                     AS national_rank,
       RANK() OVER (PARTITION BY region ORDER BY portability_per_100_beneficiaries DESC) AS region_rank,
       NTILE(4) OVER (ORDER BY portability_per_100_beneficiaries DESC)                   AS intensity_quartile
FROM vw_state_year
WHERE year = 2025 AND portability_per_100_beneficiaries IS NOT NULL
ORDER BY national_rank;


-- name: q05_interstate_destinations
-- Q5. Which states serve migrants from other states, and how does that compare with the
--     number of migrant workers who live there?
SELECT state,
       migration_role,
       ROUND(interstate_txn / 1e3, 1) AS interstate_txn_thousand,
       ROUND(100.0 * interstate_txn / SUM(interstate_txn) OVER (), 1) AS share_of_interstate_pct,
       CAST(migrants_in AS INTEGER) AS migrants_in,
       ROUND(100.0 * migrants_in / SUM(migrants_in) OVER (), 1) AS share_of_migrants_in_pct,
       ROUND(interstate_txn / migrants_in, 1) AS interstate_txn_per_migrant
FROM vw_state_year
WHERE year = 2025 AND interstate_txn IS NOT NULL
ORDER BY interstate_txn DESC
LIMIT 15;


-- name: q06_underserved_destinations
-- Q6. Destination states where inter-state portability is low for the number of migrants.
--     A state is flagged when its share of migrants is at least 3x its share of transactions.
WITH shares AS (
    SELECT state,
           migrants_in,
           interstate_txn,
           100.0 * migrants_in / SUM(migrants_in) OVER ()                      AS migrant_share_pct,
           100.0 * COALESCE(interstate_txn, 0) / SUM(interstate_txn) OVER ()   AS txn_share_pct
    FROM vw_state_year
    WHERE year = 2025 AND migrants_in IS NOT NULL
)
SELECT state,
       CAST(migrants_in AS INTEGER)     AS migrants_in,
       CAST(interstate_txn AS INTEGER)  AS interstate_txn,
       ROUND(migrant_share_pct, 2)      AS migrant_share_pct,
       ROUND(txn_share_pct, 2)          AS interstate_txn_share_pct,
       CASE WHEN interstate_txn IS NULL THEN 'Not reported' ELSE 'Low usage' END AS issue
FROM shares
WHERE migrant_share_pct >= 1.0
  AND migrant_share_pct >= 3 * txn_share_pct
ORDER BY migrant_share_pct DESC;


-- name: q07_entitlement_check
-- Q7. Do beneficiaries receive about 5 kg a month, the NFSA entitlement?
--     Deviation of each state from the national average, by year.
SELECT state,
       year,
       ROUND(kg_per_beneficiary_month, 2) AS kg_per_beneficiary_month,
       ROUND(kg_per_beneficiary_month - AVG(kg_per_beneficiary_month) OVER (PARTITION BY year), 2) AS gap_vs_national_avg,
       RANK() OVER (PARTITION BY year ORDER BY kg_per_beneficiary_month) AS rank_lowest_first
FROM fact_state_year
WHERE kg_per_beneficiary_month IS NOT NULL
ORDER BY year DESC, kg_per_beneficiary_month
LIMIT 12;


-- name: q08_deleted_cards_trend
-- Q8. Ration cards deleted each year, the three-year moving average, and the state that
--     removed the most.
WITH national AS (
    SELECT year, SUM(deleted_cards) AS deleted_cards
    FROM fact_state_year
    WHERE deleted_cards IS NOT NULL
    GROUP BY year
),
top_state AS (
    SELECT year, state, deleted_cards,
           ROW_NUMBER() OVER (PARTITION BY year ORDER BY deleted_cards DESC) AS rn
    FROM fact_state_year
    WHERE deleted_cards IS NOT NULL
)
SELECT n.year,
       ROUND(n.deleted_cards / 1e6, 2) AS deleted_cards_mn,
       ROUND(AVG(n.deleted_cards) OVER (ORDER BY n.year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / 1e6, 2) AS moving_avg_3yr_mn,
       t.state AS top_state,
       ROUND(100.0 * t.deleted_cards / n.deleted_cards, 1) AS top_state_share_pct
FROM national n
JOIN top_state t ON t.year = n.year AND t.rn = 1
ORDER BY n.year;


-- name: q09_fastest_growing_states
-- Q9. Which states grew portability fastest from 2023 to 2025?
--     Self-join of the two years; states that joined mid-period are excluded.
SELECT cur.state,
       ROUND(base.portability_txn / 1e6, 2) AS txn_2023_mn,
       ROUND(cur.portability_txn / 1e6, 2)  AS txn_2025_mn,
       ROUND(100.0 * (cur.portability_txn - base.portability_txn) / base.portability_txn, 1) AS growth_pct,
       ROUND((cur.portability_txn - base.portability_txn) / 1e6, 2) AS added_txn_mn
FROM fact_state_year cur
JOIN fact_state_year base ON base.state = cur.state AND base.year = 2023
WHERE cur.year = 2025
  AND base.portability_txn >= 100000            -- ignore tiny bases
  AND NOT EXISTS (SELECT 1 FROM fact_state_year j
                  WHERE j.state = cur.state AND j.is_onboarding_jump = 1)
ORDER BY added_txn_mn DESC
LIMIT 12;


-- name: q10_region_summary
-- Q10. Portability by region: volume, intensity and inter-state share (2025).
SELECT region,
       COUNT(*) AS states,
       ROUND(SUM(beneficiaries) / 1e6, 1)   AS beneficiaries_mn,
       ROUND(SUM(portability_txn) / 1e6, 1) AS portability_txn_mn,
       ROUND(100.0 * SUM(portability_txn) / SUM(beneficiaries), 1)   AS txn_per_100_beneficiaries,
       ROUND(100.0 * SUM(interstate_txn) / SUM(portability_txn), 2)  AS interstate_share_pct,
       ROUND(100.0 * SUM(portability_txn) / SUM(SUM(portability_txn)) OVER (), 1) AS share_of_national_pct
FROM vw_state_year
WHERE year = 2025
GROUP BY region
ORDER BY portability_txn_mn DESC;


-- name: q11_origin_vs_destination
-- Q11. Do origin states and destination states use portability differently?
SELECT migration_role,
       COUNT(*) AS states,
       ROUND(SUM(portability_txn) / 1e6, 1) AS portability_txn_mn,
       ROUND(100.0 * SUM(portability_txn) / SUM(beneficiaries), 1) AS txn_per_100_beneficiaries,
       ROUND(SUM(interstate_txn) / 1e6, 2)  AS interstate_txn_mn,
       ROUND(100.0 * SUM(interstate_txn) / SUM(portability_txn), 2) AS interstate_share_pct
FROM vw_state_year
WHERE year = 2025 AND portability_txn IS NOT NULL
GROUP BY migration_role
ORDER BY portability_txn_mn DESC;
