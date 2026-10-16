-- =============================================================================
-- 02_views.sql  |  Reusable semantic layer on top of the star schema
-- =============================================================================

-- Denormalised view: every analysis query starts here instead of repeating joins.
CREATE VIEW vw_engagement AS
SELECT
    f.period_id,
    p.period_label,
    p.period_seq,
    f.title_id,
    t.title,
    t.title_english,
    f.content_type,
    t.series_name,
    t.season_number,
    t.is_limited_series,
    t.is_live_event,
    t.language_group,
    t.is_non_english,
    t.title_origin,
    t.release_date,
    f.release_cohort,
    f.available_globally,
    f.hours_viewed,
    f.views,
    f.runtime_minutes,
    f.days_available,
    f.views_per_day
FROM fact_engagement f
JOIN dim_title  t ON t.title_id  = f.title_id
JOIN dim_period p ON p.period_id = f.period_id;

-- One row per title per period with the previous period's numbers alongside.
-- A title missing from the previous report has NULL prev_* values.
CREATE VIEW vw_title_period_change AS
SELECT
    cur.period_id,
    cur.period_label,
    cur.title_id,
    cur.title,
    cur.content_type,
    cur.release_cohort,
    cur.views          AS views,
    prev.views         AS prev_views,
    cur.hours_viewed   AS hours_viewed,
    prev.hours_viewed  AS prev_hours_viewed,
    prev.release_cohort AS prev_release_cohort
FROM vw_engagement cur
LEFT JOIN vw_engagement prev
       ON prev.title_id   = cur.title_id
      AND prev.period_seq = cur.period_seq - 1;
