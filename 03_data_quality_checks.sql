-- =============================================================================
-- 03_data_quality_checks.sql  |  Automated checks run after every load
-- Each check returns one row: name, severity, number of offending rows, note.
-- FAIL = the model is wrong and must not be used.  WARN = known source quirk.
-- =============================================================================

-- name: data_quality_checks
SELECT 'fact_duplicate_key' AS check_name, 'FAIL' AS severity,
       COUNT(*) AS offending_rows,
       'More than one row for a title in a period' AS note
FROM (SELECT period_id, title_id FROM fact_engagement GROUP BY 1, 2 HAVING COUNT(*) > 1)

UNION ALL
SELECT 'fact_orphan_title', 'FAIL', COUNT(*),
       'Fact rows whose title_id is missing from dim_title'
FROM fact_engagement f
LEFT JOIN dim_title t ON t.title_id = f.title_id
WHERE t.title_id IS NULL

UNION ALL
SELECT 'dim_title_duplicate_natural_key', 'FAIL', COUNT(*),
       'content_type + title + release_date should be unique'
FROM (SELECT content_type, title, release_date FROM dim_title GROUP BY 1, 2, 3 HAVING COUNT(*) > 1)

UNION ALL
SELECT 'release_after_period_end', 'FAIL', COUNT(*),
       'A title cannot be watched before it is released'
FROM vw_engagement e
JOIN dim_period p ON p.period_id = e.period_id
WHERE e.release_date > p.period_end

UNION ALL
SELECT 'new_release_days_out_of_range', 'FAIL', COUNT(*),
       'days_available must be between 1 and the length of the period'
FROM fact_engagement f
JOIN dim_period p ON p.period_id = f.period_id
WHERE f.days_available < 1 OR f.days_available > p.days_in_period

UNION ALL
SELECT 'views_below_reporting_threshold', 'FAIL', COUNT(*),
       'Netflix only lists titles that round to at least 100K views'
FROM fact_engagement
WHERE views < 100000

UNION ALL
SELECT 'runtime_not_reported', 'WARN', COUNT(*),
       'Runtime published as * (mostly titles still releasing episodes)'
FROM fact_engagement
WHERE runtime_minutes IS NULL

UNION ALL
SELECT 'release_date_missing', 'WARN', COUNT(*),
       'No Netflix premiere date: treated as licensed content'
FROM vw_engagement
WHERE release_date IS NULL

UNION ALL
-- Netflix defines views = hours viewed / runtime. Restricted to titles above 1M views,
-- where rounding to the nearest 100K cannot explain a gap of more than 10%.
SELECT 'views_formula_mismatch_over_10pct', 'WARN', COUNT(*),
       'views differs from hours / runtime by more than 10% (titles with 1M+ views)'
FROM fact_engagement
WHERE runtime_minutes IS NOT NULL
  AND views >= 1000000
  AND ABS(views / (hours_viewed / (runtime_minutes / 60.0)) - 1) > 0.10

UNION ALL
SELECT 'global_flag_changed_between_periods', 'WARN', COUNT(*),
       'Titles whose Available Globally flag differs across reports'
FROM (SELECT title_id FROM fact_engagement GROUP BY 1 HAVING COUNT(DISTINCT available_globally) > 1)

UNION ALL
SELECT 'show_without_season_number', 'WARN', COUNT(*),
       'Show titles where no season could be parsed from the title text'
FROM dim_title
WHERE content_type = 'Show' AND season_number IS NULL;
