/*
ATLIQ GRANDS — HOSPITALITY REVENUE INSIGHTS
MySQL 8.0 Project Script

Database: atlic_hospital
Tables expected (already imported):
  dim_date
  dim_hotels
  dim_rooms
  fact_aggregated_bookings
  fact_bookings

IMPORTANT:
1. This script assumes the five CSV tables have already been imported.
2. Run the script section-by-section in MySQL Workbench.
3. The script does not create/import source tables because the original CSV
   column definitions and import settings are not available here.
*/

-- =========================================================
-- 0. DATABASE
-- =========================================================
CREATE DATABASE IF NOT EXISTS atlic_hospital;
USE atlic_hospital;

-- Confirm tables and row counts
SHOW TABLES;

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'dim_hotels', COUNT(*) FROM dim_hotels
UNION ALL
SELECT 'dim_rooms', COUNT(*) FROM dim_rooms
UNION ALL
SELECT 'fact_aggregated_bookings', COUNT(*) FROM fact_aggregated_bookings
UNION ALL
SELECT 'fact_bookings', COUNT(*) FROM fact_bookings;

-- Inspect table structures
DESCRIBE dim_date;
DESCRIBE dim_hotels;
DESCRIBE dim_rooms;
DESCRIBE fact_aggregated_bookings;
DESCRIBE fact_bookings;


-- =========================================================
-- 1. DATA UNDERSTANDING
-- =========================================================

-- 1.1 Booking status distribution
SELECT booking_status, COUNT(*) AS total_bookings
FROM fact_bookings
GROUP BY booking_status
ORDER BY total_bookings DESC;

-- 1.2 Booking platform distribution
SELECT booking_platform, COUNT(*) AS total_bookings
FROM fact_bookings
GROUP BY booking_platform
ORDER BY total_bookings DESC;

-- 1.3 Room category distribution
SELECT room_category, COUNT(*) AS total_bookings
FROM fact_bookings
GROUP BY room_category
ORDER BY total_bookings DESC;

-- 1.4 Hotel city and category distribution
SELECT city, category, COUNT(*) AS properties
FROM dim_hotels
GROUP BY city, category
ORDER BY city, category;

-- 1.5 Room category mapping
SELECT * FROM dim_rooms ORDER BY room_id;


-- =========================================================
-- 2. DATA QUALITY CHECKS
-- =========================================================

-- 2.1 NULL checks on important booking fields
SELECT
    SUM(booking_id IS NULL) AS null_booking_id,
    SUM(property_id IS NULL) AS null_property_id,
    SUM(check_in_date IS NULL) AS null_check_in_date,
    SUM(booking_status IS NULL) AS null_booking_status,
    SUM(revenue_realized IS NULL) AS null_revenue_realized
FROM fact_bookings;

-- 2.2 Duplicate booking IDs
SELECT booking_id, COUNT(*) AS duplicate_count
FROM fact_bookings
GROUP BY booking_id
HAVING COUNT(*) > 1;

-- 2.3 Invalid guest counts
SELECT COUNT(*) AS invalid_guest_rows
FROM fact_bookings
WHERE no_guests <= 0;

-- 2.4 Negative revenue
SELECT COUNT(*) AS negative_revenue_rows
FROM fact_bookings
WHERE revenue_generated < 0 OR revenue_realized < 0;

-- 2.5 Invalid stay date order
-- check_in_date and checkout_date are stored as ISO text (YYYY-MM-DD)
SELECT COUNT(*) AS invalid_stay_date_rows
FROM fact_bookings
WHERE STR_TO_DATE(check_in_date, '%Y-%m-%d') IS NULL
   OR STR_TO_DATE(checkout_date, '%Y-%m-%d') IS NULL
   OR STR_TO_DATE(checkout_date, '%Y-%m-%d')
      < STR_TO_DATE(check_in_date, '%Y-%m-%d');

-- 2.6 Successful bookings exceeding capacity
SELECT COUNT(*) AS over_capacity_rows
FROM fact_aggregated_bookings
WHERE successful_bookings > capacity;

-- 2.7 Invalid dates in aggregated bookings
SELECT COUNT(*) AS invalid_aggregated_dates
FROM fact_aggregated_bookings
WHERE STR_TO_DATE(check_in_date, '%Y-%m-%d') IS NULL;


-- =========================================================
-- 3. JOINS & CORE ANALYSIS
-- =========================================================

-- 3.1 Property-wise bookings
SELECT
    h.property_id, h.property_name, h.city,
    COUNT(b.booking_id) AS total_bookings
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
ORDER BY total_bookings DESC;

-- 3.2 City-wise bookings
SELECT h.city, COUNT(b.booking_id) AS total_bookings
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.city
ORDER BY total_bookings DESC;

-- 3.3 Hotel category-wise bookings
SELECT h.category, COUNT(b.booking_id) AS total_bookings
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.category
ORDER BY total_bookings DESC;

-- 3.4 Room category-wise bookings
SELECT
    r.room_class,
    COUNT(b.booking_id) AS total_bookings
FROM fact_bookings b
JOIN dim_rooms r ON b.room_category = r.room_id
GROUP BY r.room_class
ORDER BY total_bookings DESC;

-- 3.5 Property-wise realized revenue
SELECT
    h.property_id, h.property_name, h.city,
    SUM(b.revenue_realized) AS total_revenue
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
ORDER BY total_revenue DESC;

-- 3.6 City-wise realized revenue
SELECT h.city, SUM(b.revenue_realized) AS total_revenue
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.city
ORDER BY total_revenue DESC;

-- 3.7 Room class-wise realized revenue
SELECT
    r.room_class,
    SUM(b.revenue_realized) AS total_revenue
FROM fact_bookings b
JOIN dim_rooms r ON b.room_category = r.room_id
GROUP BY r.room_class
ORDER BY total_revenue DESC;

-- 3.8 Platform-wise revenue
SELECT
    booking_platform,
    SUM(revenue_realized) AS total_revenue
FROM fact_bookings
GROUP BY booking_platform
ORDER BY total_revenue DESC;

-- 3.9 Weekday vs weekend bookings and revenue
-- dim_date.date is stored like 1-May-22; fact check_in_date is YYYY-MM-DD.
SELECT
    d.day_type,
    COUNT(b.booking_id) AS total_bookings,
    SUM(b.revenue_realized) AS total_revenue
FROM fact_bookings b
JOIN dim_date d
  ON STR_TO_DATE(b.check_in_date, '%Y-%m-%d')
   = STR_TO_DATE(d.date, '%e-%b-%y')
GROUP BY d.day_type
ORDER BY total_revenue DESC;

-- 3.10 Property-wise average rating
SELECT
    h.property_id, h.property_name, h.city,
    ROUND(AVG(CAST(NULLIF(b.ratings_given, '') AS DECIMAL(4,2))), 2)
      AS avg_rating
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
ORDER BY avg_rating DESC;

-- 3.11 City-wise average rating
SELECT
    h.city,
    ROUND(AVG(CAST(NULLIF(b.ratings_given, '') AS DECIMAL(4,2))), 2)
      AS avg_rating
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.city
ORDER BY avg_rating DESC;

-- 3.12 Platform-wise average rating
SELECT
    booking_platform,
    COUNT(ratings_given) AS rated_bookings,
    ROUND(AVG(CAST(NULLIF(ratings_given, '') AS DECIMAL(4,2))), 2)
      AS avg_rating
FROM fact_bookings
GROUP BY booking_platform
ORDER BY avg_rating DESC;


-- =========================================================
-- 4. CANCELLATION & NO-SHOW ANALYSIS
-- =========================================================

-- 4.1 Platform cancellation counts
SELECT
    booking_platform,
    SUM(booking_status = 'Cancelled') AS cancelled_bookings
FROM fact_bookings
GROUP BY booking_platform
ORDER BY cancelled_bookings DESC;

-- 4.2 Platform cancellation rates
SELECT
    booking_platform,
    COUNT(*) AS total_bookings,
    SUM(booking_status = 'Cancelled') AS cancelled_bookings,
    ROUND(
        100.0 * SUM(booking_status = 'Cancelled') / COUNT(*), 2
    ) AS cancellation_rate_pct
FROM fact_bookings
GROUP BY booking_platform
ORDER BY cancellation_rate_pct DESC;

-- 4.3 Property cancellation and no-show rates
SELECT
    h.property_id, h.property_name, h.city,
    COUNT(*) AS total_bookings,
    SUM(b.booking_status = 'Cancelled') AS cancelled_bookings,
    ROUND(100.0 * SUM(b.booking_status = 'Cancelled') / COUNT(*), 2)
      AS cancellation_rate_pct,
    SUM(b.booking_status = 'No Show') AS no_show_bookings,
    ROUND(100.0 * SUM(b.booking_status = 'No Show') / COUNT(*), 2)
      AS no_show_rate_pct
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
ORDER BY cancellation_rate_pct DESC;

-- 4.4 City cancellation and no-show rates
SELECT
    h.city,
    COUNT(*) AS total_bookings,
    ROUND(100.0 * SUM(b.booking_status = 'Cancelled') / COUNT(*), 2)
      AS cancellation_rate_pct,
    ROUND(100.0 * SUM(b.booking_status = 'No Show') / COUNT(*), 2)
      AS no_show_rate_pct
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.city
ORDER BY cancellation_rate_pct DESC;


-- =========================================================
-- 5. AGGREGATED BOOKINGS / CAPACITY
-- =========================================================

-- 5.1 Property-wise successful bookings and capacity
SELECT
    h.property_id, h.property_name, h.city,
    SUM(a.successful_bookings) AS successful_bookings,
    SUM(a.capacity) AS total_capacity,
    ROUND(
        100.0 * SUM(a.successful_bookings) / NULLIF(SUM(a.capacity), 0), 2
    ) AS occupancy_pct
FROM fact_aggregated_bookings a
JOIN dim_hotels h ON a.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
ORDER BY occupancy_pct DESC;

-- 5.2 Room category-wise occupancy
SELECT
    r.room_class,
    SUM(a.successful_bookings) AS successful_bookings,
    SUM(a.capacity) AS total_capacity,
    ROUND(
        100.0 * SUM(a.successful_bookings) / NULLIF(SUM(a.capacity), 0), 2
    ) AS occupancy_pct
FROM fact_aggregated_bookings a
JOIN dim_rooms r ON a.room_category = r.room_id
GROUP BY r.room_class
ORDER BY occupancy_pct DESC;

-- 5.3 City-wise occupancy
SELECT
    h.city,
    SUM(a.successful_bookings) AS successful_bookings,
    SUM(a.capacity) AS total_capacity,
    ROUND(
        100.0 * SUM(a.successful_bookings) / NULLIF(SUM(a.capacity), 0), 2
    ) AS occupancy_pct
FROM fact_aggregated_bookings a
JOIN dim_hotels h ON a.property_id = h.property_id
GROUP BY h.city
ORDER BY occupancy_pct DESC;


-- =========================================================
-- 6. CTEs
-- =========================================================

-- 6.1 Platform revenue contribution
WITH platform_revenue AS (
    SELECT
        booking_platform,
        SUM(revenue_realized) AS total_revenue
    FROM fact_bookings
    GROUP BY booking_platform
)
SELECT
    booking_platform,
    total_revenue,
    ROUND(
        100.0 * total_revenue / SUM(total_revenue) OVER (), 2
    ) AS revenue_contribution_pct
FROM platform_revenue
ORDER BY total_revenue DESC;

-- 6.2 Property revenue ranking
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM property_revenue
ORDER BY revenue_rank;

-- 6.3 Top 3 properties in each city
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
),
ranked_properties AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY city ORDER BY total_revenue DESC
        ) AS city_rank
    FROM property_revenue
)
SELECT *
FROM ranked_properties
WHERE city_rank <= 3
ORDER BY city, city_rank;

-- 6.4 Monthly revenue and previous month revenue
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m')
          AS revenue_month,
        SUM(revenue_realized) AS total_revenue
    FROM fact_bookings
    GROUP BY DATE_FORMAT(
        STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m'
    )
),
monthly_comparison AS (
    SELECT
        revenue_month,
        total_revenue,
        LAG(total_revenue) OVER (ORDER BY revenue_month)
          AS previous_month_revenue
    FROM monthly_revenue
)
SELECT
    revenue_month,
    total_revenue,
    previous_month_revenue,
    total_revenue - previous_month_revenue AS revenue_difference,
    ROUND(
        100.0 * (total_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0), 2
    ) AS mom_growth_pct
FROM monthly_comparison
ORDER BY revenue_month;


-- =========================================================
-- 7. SUBQUERIES
-- =========================================================

-- 7.1 Properties earning above the average property revenue
SELECT *
FROM (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
) AS property_totals
WHERE total_revenue > (
    SELECT AVG(property_revenue)
    FROM (
        SELECT SUM(revenue_realized) AS property_revenue
        FROM fact_bookings
        GROUP BY property_id
    ) AS average_by_property
)
ORDER BY total_revenue DESC;

-- 7.2 Second-highest revenue property
SELECT
    h.property_id, h.property_name, h.city,
    SUM(b.revenue_realized) AS total_revenue
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city
HAVING total_revenue = (
    SELECT MAX(second_level_revenue)
    FROM (
        SELECT SUM(revenue_realized) AS second_level_revenue
        FROM fact_bookings
        GROUP BY property_id
        ORDER BY second_level_revenue DESC
        LIMIT 1 OFFSET 1
    ) AS second_highest
);

-- 7.3 Properties with no cancelled bookings
SELECT h.property_id, h.property_name, h.city
FROM dim_hotels h
WHERE h.property_id NOT IN (
    SELECT property_id
    FROM fact_bookings
    WHERE booking_status = 'Cancelled'
      AND property_id IS NOT NULL
);


-- =========================================================
-- 8. WINDOW FUNCTIONS
-- =========================================================

-- 8.1 Revenue difference from previous property (LAG)
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
),
ranked AS (
    SELECT
        *,
        LAG(total_revenue) OVER (ORDER BY total_revenue DESC)
          AS previous_revenue
    FROM property_revenue
)
SELECT
    *,
    previous_revenue - total_revenue AS revenue_gap_from_previous
FROM ranked
ORDER BY total_revenue DESC;

-- 8.2 Revenue of next property (LEAD)
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    LEAD(total_revenue) OVER (ORDER BY total_revenue DESC)
      AS next_property_revenue
FROM property_revenue
ORDER BY total_revenue DESC;

-- 8.3 Rank properties within each city
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    RANK() OVER (
        PARTITION BY city ORDER BY total_revenue DESC
    ) AS city_rank
FROM property_revenue
ORDER BY city, city_rank;

-- 8.4 City total revenue beside each property
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    SUM(total_revenue) OVER (PARTITION BY city) AS city_total_revenue
FROM property_revenue
ORDER BY city, total_revenue DESC;

-- 8.5 City average property revenue beside each property
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    ROUND(AVG(total_revenue) OVER (PARTITION BY city), 2)
      AS city_avg_revenue
FROM property_revenue
ORDER BY city, total_revenue DESC;

-- 8.6 Percent rank within each city
WITH property_revenue AS (
    SELECT
        h.property_id, h.property_name, h.city,
        SUM(b.revenue_realized) AS total_revenue
    FROM fact_bookings b
    JOIN dim_hotels h ON b.property_id = h.property_id
    GROUP BY h.property_id, h.property_name, h.city
)
SELECT
    *,
    ROUND(
        PERCENT_RANK() OVER (
            PARTITION BY city ORDER BY total_revenue DESC
        ), 2
    ) AS revenue_percent_rank
FROM property_revenue
ORDER BY city, total_revenue DESC;

-- 8.7 Running total of monthly revenue
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m')
          AS revenue_month,
        SUM(revenue_realized) AS total_revenue
    FROM fact_bookings
    GROUP BY DATE_FORMAT(
        STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m'
    )
)
SELECT
    revenue_month,
    total_revenue,
    SUM(total_revenue) OVER (
        ORDER BY revenue_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total_revenue
FROM monthly_revenue
ORDER BY revenue_month;


-- =========================================================
-- 9. POWER BI-READY VIEWS
-- Run these after checking the queries above.
-- =========================================================

-- 9.1 Property performance
CREATE OR REPLACE VIEW vw_property_performance AS
SELECT
    h.property_id,
    h.property_name,
    h.city,
    h.category,
    COUNT(b.booking_id) AS total_bookings,
    SUM(b.revenue_generated) AS revenue_generated,
    SUM(b.revenue_realized) AS revenue_realized,
    SUM(b.booking_status = 'Cancelled') AS cancelled_bookings,
    SUM(b.booking_status = 'No Show') AS no_show_bookings,
    ROUND(
        100.0 * SUM(b.booking_status = 'Cancelled') / NULLIF(COUNT(*), 0), 2
    ) AS cancellation_rate_pct,
    ROUND(
        100.0 * SUM(b.booking_status = 'No Show') / NULLIF(COUNT(*), 0), 2
    ) AS no_show_rate_pct,
    ROUND(
        AVG(CAST(NULLIF(b.ratings_given, '') AS DECIMAL(4,2))), 2
    ) AS avg_rating
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY
    h.property_id, h.property_name, h.city, h.category;

-- 9.2 Monthly revenue
CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT
    DATE_FORMAT(STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m')
      AS revenue_month,
    SUM(revenue_generated) AS revenue_generated,
    SUM(revenue_realized) AS revenue_realized,
    COUNT(booking_id) AS total_bookings,
    SUM(booking_status = 'Cancelled') AS cancelled_bookings,
    SUM(booking_status = 'No Show') AS no_show_bookings
FROM fact_bookings
GROUP BY DATE_FORMAT(
    STR_TO_DATE(check_in_date, '%Y-%m-%d'), '%Y-%m'
);

-- 9.3 City performance
CREATE OR REPLACE VIEW vw_city_performance AS
SELECT
    h.city,
    COUNT(b.booking_id) AS total_bookings,
    SUM(b.revenue_generated) AS revenue_generated,
    SUM(b.revenue_realized) AS revenue_realized,
    ROUND(
        100.0 * SUM(b.booking_status = 'Cancelled') / NULLIF(COUNT(*), 0), 2
    ) AS cancellation_rate_pct,
    ROUND(
        AVG(CAST(NULLIF(b.ratings_given, '') AS DECIMAL(4,2))), 2
    ) AS avg_rating
FROM fact_bookings b
JOIN dim_hotels h ON b.property_id = h.property_id
GROUP BY h.city;

-- 9.4 Platform performance
CREATE OR REPLACE VIEW vw_platform_performance AS
SELECT
    booking_platform,
    COUNT(booking_id) AS total_bookings,
    SUM(revenue_generated) AS revenue_generated,
    SUM(revenue_realized) AS revenue_realized,
    SUM(booking_status = 'Cancelled') AS cancelled_bookings,
    ROUND(
        100.0 * SUM(booking_status = 'Cancelled') / NULLIF(COUNT(*), 0), 2
    ) AS cancellation_rate_pct,
    ROUND(
        AVG(CAST(NULLIF(ratings_given, '') AS DECIMAL(4,2))), 2
    ) AS avg_rating
FROM fact_bookings
GROUP BY booking_platform;

-- 9.5 Room category performance
CREATE OR REPLACE VIEW vw_room_performance AS
SELECT
    r.room_id,
    r.room_class,
    COUNT(b.booking_id) AS total_bookings,
    SUM(b.revenue_generated) AS revenue_generated,
    SUM(b.revenue_realized) AS revenue_realized,
    ROUND(
        AVG(CAST(NULLIF(b.ratings_given, '') AS DECIMAL(4,2))), 2
    ) AS avg_rating
FROM fact_bookings b
JOIN dim_rooms r ON b.room_category = r.room_id
GROUP BY r.room_id, r.room_class;

-- 9.6 Occupancy performance by property
CREATE OR REPLACE VIEW vw_property_occupancy AS
SELECT
    h.property_id,
    h.property_name,
    h.city,
    SUM(a.successful_bookings) AS successful_bookings,
    SUM(a.capacity) AS total_capacity,
    SUM(a.capacity) - SUM(a.successful_bookings) AS unoccupied_capacity,
    ROUND(
        100.0 * SUM(a.successful_bookings) / NULLIF(SUM(a.capacity), 0), 2
    ) AS occupancy_pct
FROM fact_aggregated_bookings a
JOIN dim_hotels h ON a.property_id = h.property_id
GROUP BY h.property_id, h.property_name, h.city;

-- 9.7 Daily occupancy trend
CREATE OR REPLACE VIEW vw_daily_occupancy AS
SELECT
    a.check_in_date,
    a.property_id,
    h.property_name,
    h.city,
    SUM(a.successful_bookings) AS successful_bookings,
    SUM(a.capacity) AS total_capacity,
    ROUND(
        100.0 * SUM(a.successful_bookings) / NULLIF(SUM(a.capacity), 0), 2
    ) AS occupancy_pct
FROM fact_aggregated_bookings a
JOIN dim_hotels h ON a.property_id = h.property_id
GROUP BY a.check_in_date, a.property_id, h.property_name, h.city;


-- =========================================================
-- 10. VALIDATE VIEWS / FINAL DATASETS
-- =========================================================
SELECT * FROM vw_property_performance ORDER BY revenue_realized DESC;
SELECT * FROM vw_monthly_revenue ORDER BY revenue_month;
SELECT * FROM vw_city_performance ORDER BY revenue_realized DESC;
SELECT * FROM vw_platform_performance ORDER BY revenue_realized DESC;
SELECT * FROM vw_room_performance ORDER BY revenue_realized DESC;
SELECT * FROM vw_property_occupancy ORDER BY occupancy_pct DESC;
SELECT * FROM vw_daily_occupancy ORDER BY check_in_date, property_id;

-- End of project script.
