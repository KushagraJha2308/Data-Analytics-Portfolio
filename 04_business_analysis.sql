-- =============================================================================
-- 04_business_analysis.sql  |  Business questions answered in SQL
-- Each block starts with "-- name:" so run_sql.py can export it to its own CSV.
-- Dialect: SQLite 3.35+ (CTEs and window functions are standard SQL and run
-- unchanged on PostgreSQL / MySQL 8 apart from strftime).
-- =============================================================================


-- name: q01_period_kpis
-- Q1. How large is total engagement each half-year, and how is it trending?
WITH period_totals AS (
    SELECT period_id,
           period_label,
           period_seq,
           COUNT(*)          AS titles,
           SUM(hours_viewed) AS hours_viewed,
           SUM(views)        AS views
    FROM vw_engagement
    GROUP BY period_id, period_label, period_seq
)
SELECT period_label,
       titles,
       ROUND(hours_viewed / 1e9, 2) AS hours_bn,
       ROUND(views / 1e9, 2)        AS views_bn,
       ROUND(100.0 * (hours_viewed - LAG(hours_viewed) OVER w) / LAG(hours_viewed) OVER w, 1) AS hours_growth_pct,
       ROUND(100.0 * (views - LAG(views) OVER w) / LAG(views) OVER w, 1)                      AS views_growth_pct,
       ROUND(1.0 * hours_viewed / titles / 1e6, 2) AS avg_hours_per_title_mn
FROM period_totals
WINDOW w AS (ORDER BY period_seq)
ORDER BY period_seq;


-- name: q02_metric_mix_by_content_type
-- Q2. Does the choice of metric change the story? Share of hours vs share of views.
SELECT period_label,
       content_type,
       ROUND(100.0 * SUM(hours_viewed) / SUM(SUM(hours_viewed)) OVER (PARTITION BY period_label), 1) AS share_of_hours_pct,
       ROUND(100.0 * SUM(views)        / SUM(SUM(views))        OVER (PARTITION BY period_label), 1) AS share_of_views_pct,
       ROUND(100.0 * COUNT(*)          / SUM(COUNT(*))          OVER (PARTITION BY period_label), 1) AS share_of_titles_pct
FROM vw_engagement
GROUP BY period_label, content_type
ORDER BY period_label, content_type;


-- name: q03_pareto_concentration
-- Q3. How concentrated is viewing? What share of titles delivers 80% of hours?
WITH ranked AS (
    SELECT period_label,
           content_type,
           hours_viewed,
           ROW_NUMBER() OVER w AS title_rank,
           COUNT(*) OVER (PARTITION BY period_label, content_type) AS total_titles,
           SUM(hours_viewed) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_hours,
           SUM(hours_viewed) OVER (PARTITION BY period_label, content_type)            AS total_hours
    FROM vw_engagement
    WINDOW w AS (PARTITION BY period_label, content_type ORDER BY hours_viewed DESC, title_id)
)
SELECT period_label,
       content_type,
       MAX(total_titles) AS total_titles,
       MIN(CASE WHEN 1.0 * running_hours / total_hours >= 0.80 THEN title_rank END) AS titles_for_80pct_hours,
       ROUND(100.0 * MIN(CASE WHEN 1.0 * running_hours / total_hours >= 0.80 THEN title_rank END)
             / MAX(total_titles), 1) AS pct_of_titles_for_80pct_hours,
       ROUND(100.0 * SUM(CASE WHEN title_rank <= total_titles * 0.01 THEN hours_viewed END) / MAX(total_hours), 1) AS top_1pct_share_of_hours,
       ROUND(100.0 * SUM(CASE WHEN title_rank <= total_titles * 0.10 THEN hours_viewed END) / MAX(total_hours), 1) AS top_10pct_share_of_hours
FROM ranked
GROUP BY period_label, content_type
ORDER BY period_label, content_type;


-- name: q04_decile_contribution
-- Q4. How much does each decile of the catalogue contribute? (latest period)
WITH deciles AS (
    SELECT content_type,
           hours_viewed,
           NTILE(10) OVER (PARTITION BY content_type ORDER BY hours_viewed DESC) AS decile
    FROM vw_engagement
    WHERE period_id = (SELECT MAX(period_id) FROM dim_period)
)
SELECT content_type,
       decile,
       COUNT(*)                         AS titles,
       ROUND(SUM(hours_viewed) / 1e9, 2) AS hours_bn,
       ROUND(100.0 * SUM(hours_viewed) / SUM(SUM(hours_viewed)) OVER (PARTITION BY content_type), 1) AS share_of_hours_pct
FROM deciles
GROUP BY content_type, decile
ORDER BY content_type, decile;


-- name: q05_release_cohort_efficiency
-- Q5. New releases vs Netflix back catalogue vs licensed content:
--     who makes up the catalogue, and who earns the viewing?
--     efficiency_index > 1 means the cohort earns more than its share of titles.
SELECT period_label,
       release_cohort,
       COUNT(*) AS titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER p, 1)                   AS share_of_titles_pct,
       ROUND(100.0 * SUM(hours_viewed) / SUM(SUM(hours_viewed)) OVER p, 1) AS share_of_hours_pct,
       ROUND((1.0 * SUM(hours_viewed) / SUM(SUM(hours_viewed)) OVER p)
             / (1.0 * COUNT(*) / SUM(COUNT(*)) OVER p), 2)                 AS efficiency_index,
       ROUND(SUM(hours_viewed) / 1e6 / COUNT(*), 2)                        AS avg_hours_per_title_mn
FROM vw_engagement
GROUP BY period_label, release_cohort
WINDOW p AS (PARTITION BY period_label)
ORDER BY period_label, share_of_hours_pct DESC;


-- name: q06_top10_with_rank_change
-- Q6. Top 10 titles per content type in the latest period, and where they ranked before.
WITH ranked AS (
    SELECT period_seq,
           period_label,
           title_id,
           title_english,
           content_type,
           release_cohort,
           views,
           DENSE_RANK() OVER (PARTITION BY period_seq, content_type ORDER BY views DESC) AS views_rank
    FROM vw_engagement
)
SELECT cur.content_type,
       cur.views_rank,
       cur.title_english,
       cur.release_cohort,
       ROUND(cur.views / 1e6, 1) AS views_mn,
       prev.views_rank           AS prev_period_rank,
       CASE
           WHEN prev.views_rank IS NULL THEN 'New entry'
           WHEN prev.views_rank > cur.views_rank THEN 'Up ' || (prev.views_rank - cur.views_rank)
           WHEN prev.views_rank < cur.views_rank THEN 'Down ' || (cur.views_rank - prev.views_rank)
           ELSE 'No change'
       END AS movement
FROM ranked cur
LEFT JOIN ranked prev
       ON prev.title_id = cur.title_id
      AND prev.period_seq = cur.period_seq - 1
WHERE cur.period_seq = (SELECT MAX(period_seq) FROM dim_period)
  AND cur.views_rank <= 10
ORDER BY cur.content_type, cur.views_rank;


-- name: q07_launch_month_carry_over
-- Q7. Launch-timing bias. For titles released inside a period, how many views do they
--     collect in the NEXT period relative to their launch period?
--     A high carry-over ratio means the launch-period ranking understated the title.
WITH launches AS (
    SELECT cur.content_type,
           -- month position inside the half-year: 1 = first month, 6 = last month
           ((CAST(strftime('%m', cur.release_date) AS INTEGER) - 1) % 6) + 1 AS month_in_period,
           cur.title_english,
           cur.views              AS launch_period_views,
           COALESCE(nxt.views, 0) AS next_period_views
    FROM vw_engagement cur
    LEFT JOIN vw_engagement nxt
           ON nxt.title_id = cur.title_id
          AND nxt.period_seq = cur.period_seq + 1
    WHERE cur.release_cohort = 'New release'
      AND cur.period_seq < (SELECT MAX(period_seq) FROM dim_period)   -- needs a following period
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY content_type, month_in_period
                              ORDER BY next_period_views DESC) AS carry_rank
    FROM launches
)
SELECT content_type,
       month_in_period,
       COUNT(*) AS titles_launched,
       ROUND(SUM(launch_period_views) / 1e6, 1) AS launch_period_views_mn,
       ROUND(SUM(next_period_views) / 1e6, 1)   AS next_period_views_mn,
       ROUND(100.0 * SUM(next_period_views) / SUM(launch_period_views), 1) AS carry_over_pct,
       -- same ratio without the single biggest carry-over title, to show how one hit skews it
       ROUND(100.0 * SUM(CASE WHEN carry_rank > 1 THEN next_period_views END)
             / SUM(CASE WHEN carry_rank > 1 THEN launch_period_views END), 1) AS carry_over_pct_excl_top_title
FROM ranked
GROUP BY content_type, month_in_period
ORDER BY content_type, month_in_period;


-- name: q08_franchise_halo
-- Q8. Franchise halo. When a show releases a new season, what happens to viewing of its
--     EARLIER seasons compared with the previous period? Control group = earlier seasons
--     of shows that had no new season in either period.
WITH new_season_launch AS (
    SELECT period_seq,
           series_name,
           MAX(season_number) AS launched_season
    FROM vw_engagement
    WHERE content_type = 'Show'
      AND release_cohort = 'New release'
      AND is_limited_series = 0
      AND season_number >= 2
    GROUP BY period_seq, series_name
),
back_seasons AS (
    SELECT cur.period_seq,
           cur.period_label,
           cur.series_name,
           cur.season_number,
           cur.views  AS views,
           prev.views AS prev_views,
           cur.hours_viewed  AS hours_viewed,
           prev.hours_viewed AS prev_hours_viewed
    FROM vw_engagement cur
    JOIN vw_engagement prev
      ON prev.title_id = cur.title_id
     AND prev.period_seq = cur.period_seq - 1
    WHERE cur.content_type = 'Show'
      AND cur.season_number IS NOT NULL
      AND cur.release_cohort  <> 'New release'
      AND prev.release_cohort <> 'New release'
),
labelled AS (
    SELECT b.*,
           CASE WHEN n.series_name IS NOT NULL AND b.season_number < n.launched_season
                THEN 'New season launched'
                ELSE 'No new season'
           END AS series_group
    FROM back_seasons b
    LEFT JOIN new_season_launch n
           ON n.series_name = b.series_name
          AND n.period_seq  = b.period_seq
    -- exclude series still decaying from a launch in the previous period
    WHERE NOT EXISTS (SELECT 1 FROM new_season_launch p
                      WHERE p.series_name = b.series_name
                        AND p.period_seq  = b.period_seq - 1)
)
SELECT period_label,
       series_group,
       COUNT(DISTINCT series_name) AS series,
       COUNT(*)                    AS back_seasons,
       ROUND(SUM(prev_views) / 1e6, 1) AS prev_period_views_mn,
       ROUND(SUM(views) / 1e6, 1)      AS current_views_mn,
       ROUND(100.0 * (SUM(views) - SUM(prev_views)) / SUM(prev_views), 1) AS views_change_pct,
       ROUND((SUM(hours_viewed) - SUM(prev_hours_viewed)) / 1e6, 1)       AS incremental_hours_mn
FROM labelled
GROUP BY period_label, series_group
ORDER BY period_label, series_group;


-- name: q09_viewing_bridge
-- Q9. Viewing bridge. Decompose the change in hours between consecutive periods into
--     titles that entered the report, titles that left it, and titles in both.
WITH pairs AS (
    -- titles present in the current period (new or retained)
    SELECT cur.period_seq,
           cur.period_label,
           CASE WHEN prev.title_id IS NULL AND cur.release_cohort = 'New release' THEN '1. New releases'
                WHEN prev.title_id IS NULL THEN '2. Catalogue titles entering the report'
                WHEN cur.hours_viewed >= prev.hours_viewed THEN '3. Retained titles - growing'
                ELSE '4. Retained titles - declining'
           END AS component,
           cur.hours_viewed - COALESCE(prev.hours_viewed, 0) AS hours_delta
    FROM vw_engagement cur
    LEFT JOIN vw_engagement prev
           ON prev.title_id = cur.title_id
          AND prev.period_seq = cur.period_seq - 1
    WHERE cur.period_seq > 1

    UNION ALL
    -- titles that dropped out of the report
    SELECT prev.period_seq + 1,
           p.period_label,
           '5. Titles leaving the report',
           -prev.hours_viewed
    FROM vw_engagement prev
    JOIN dim_period p ON p.period_seq = prev.period_seq + 1
    WHERE NOT EXISTS (SELECT 1 FROM fact_engagement cur
                      WHERE cur.title_id = prev.title_id
                        AND cur.period_id = p.period_id)
)
SELECT period_label,
       component,
       COUNT(*) AS titles,
       ROUND(SUM(hours_delta) / 1e9, 2) AS hours_delta_bn
FROM pairs
GROUP BY period_label, component
ORDER BY period_label, component;


-- name: q10_language_group_trend
-- Q10. Which original-language groups are gaining or losing share of viewing?
--      NOTE: language is inferred from the script of the native title, so Latin-script
--      languages that Netflix lists without a separate English title are undercounted.
WITH by_language AS (
    SELECT period_seq,
           period_label,
           language_group,
           COUNT(*)          AS titles,
           SUM(hours_viewed) AS hours_viewed
    FROM vw_engagement
    GROUP BY period_seq, period_label, language_group
)
SELECT period_label,
       language_group,
       titles,
       ROUND(hours_viewed / 1e9, 2) AS hours_bn,
       ROUND(100.0 * hours_viewed / SUM(hours_viewed) OVER (PARTITION BY period_seq), 2) AS share_of_hours_pct,
       ROUND(100.0 * (hours_viewed - LAG(hours_viewed) OVER lang) / LAG(hours_viewed) OVER lang, 1) AS hours_growth_pct
FROM by_language
WINDOW lang AS (PARTITION BY language_group ORDER BY period_seq)
ORDER BY period_seq, hours_viewed DESC;


-- name: q11_global_availability
-- Q11. Do globally available titles outperform regionally licensed ones?
SELECT period_label,
       content_type,
       CASE available_globally WHEN 1 THEN 'Global' ELSE 'Regional' END AS availability,
       COUNT(*) AS titles,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER p, 1)                   AS share_of_titles_pct,
       ROUND(100.0 * SUM(hours_viewed) / SUM(SUM(hours_viewed)) OVER p, 1) AS share_of_hours_pct,
       ROUND(AVG(views) / 1e6, 2) AS avg_views_mn
FROM vw_engagement
GROUP BY period_label, content_type, available_globally
WINDOW p AS (PARTITION BY period_label, content_type)
ORDER BY period_label, content_type, availability;


-- name: q12_new_show_format_performance
-- Q12. For newly released shows, which format launches strongest:
--      limited series, a brand-new season 1, or a returning season?
SELECT CASE WHEN is_limited_series = 1 THEN 'Limited series'
            WHEN season_number >= 2    THEN 'Returning season'
            ELSE 'New season 1'
       END AS show_format,
       COUNT(*) AS launches,
       ROUND(AVG(views) / 1e6, 1)        AS avg_views_mn,
       ROUND(SUM(views) / 1e9, 2)        AS total_views_bn,
       ROUND(AVG(runtime_minutes) / 60.0, 1) AS avg_runtime_hours,
       ROUND(SUM(hours_viewed) / 1e9, 2) AS total_hours_bn
FROM vw_engagement
WHERE content_type = 'Show'
  AND release_cohort = 'New release'
  AND is_live_event = 0
  AND season_number IS NOT NULL
GROUP BY show_format
ORDER BY avg_views_mn DESC;


-- name: q13_franchise_leaderboard
-- Q13. Which franchises (all seasons combined) drive the most hours in the latest period,
--      and how much of that comes from back seasons rather than the newest one?
WITH franchise AS (
    SELECT series_name,
           title_origin,
           COUNT(*)          AS seasons_watched,
           SUM(hours_viewed) AS hours_viewed,
           SUM(CASE WHEN release_cohort <> 'New release' THEN hours_viewed ELSE 0 END) AS back_catalogue_hours
    FROM vw_engagement
    WHERE content_type = 'Show'
      AND period_id = (SELECT MAX(period_id) FROM dim_period)
    GROUP BY series_name, title_origin
)
SELECT RANK() OVER (ORDER BY hours_viewed DESC) AS franchise_rank,
       series_name,
       title_origin,
       seasons_watched,
       ROUND(hours_viewed / 1e6, 1) AS hours_mn,
       ROUND(100.0 * back_catalogue_hours / hours_viewed, 1) AS back_catalogue_share_pct
FROM franchise
ORDER BY hours_viewed DESC
LIMIT 20;


-- name: q14_biggest_movers
-- Q14. Which titles already past their launch period gained or lost the most views
--      versus the previous period? Five biggest risers and fallers per period.
WITH changes AS (
    SELECT period_label,
           title,
           content_type,
           prev_views,
           views,
           views - prev_views AS views_change,
           ROW_NUMBER() OVER (PARTITION BY period_label ORDER BY views - prev_views DESC) AS riser_rank,
           ROW_NUMBER() OVER (PARTITION BY period_label ORDER BY views - prev_views ASC)  AS faller_rank
    FROM vw_title_period_change
    WHERE prev_views IS NOT NULL
      AND release_cohort <> 'New release'
      AND prev_release_cohort <> 'New release'
)
SELECT period_label,
       CASE WHEN riser_rank <= 5 THEN 'Riser' ELSE 'Faller' END AS direction,
       title,
       content_type,
       ROUND(prev_views / 1e6, 1)   AS prev_views_mn,
       ROUND(views / 1e6, 1)        AS views_mn,
       ROUND(views_change / 1e6, 1) AS change_mn,
       ROUND(100.0 * views_change / prev_views, 1) AS change_pct
FROM changes
WHERE riser_rank <= 5 OR faller_rank <= 5
ORDER BY period_label, direction DESC, views_change DESC;
