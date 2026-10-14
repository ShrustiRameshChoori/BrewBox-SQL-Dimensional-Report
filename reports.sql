-- =====================================================
-- reports.sql  |  BrewBox Coffee Roasters - Analytics
-- Run after schema.sql and data.sql (MySQL 8.0+)
-- =====================================================
USE brewbox_dw;

-- =====================================================
-- REPORT 1: Star-join view (fact + all 4 dimensions)
-- =====================================================
DROP VIEW IF EXISTS vw_sales_detail;
CREATE VIEW vw_sales_detail AS
SELECT  f.sales_key, f.order_id, d.full_date, d.year_num, d.month_num, d.month_name,
        p.product_name, p.category, c.customer_name, c.segment,
        s.store_name, s.region, s.city AS store_city,
        f.quantity, f.unit_price, f.discount_amount, f.total_amount
FROM fact_sales f
JOIN dim_date     d ON f.date_key     = d.date_key
JOIN dim_product  p ON f.product_key  = p.product_key
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_store    s ON f.store_key    = s.store_key;

SELECT * FROM vw_sales_detail ORDER BY full_date, sales_key LIMIT 10;

-- =====================================================
-- REPORT 2: WINDOW FUNCTION RANKINGS
-- =====================================================

-- 2.1 Product ranking: ROW_NUMBER vs RANK vs DENSE_RANK
SELECT  p.product_name, p.category,
        SUM(f.quantity)     AS units_sold,
        SUM(f.total_amount) AS revenue,
        ROW_NUMBER() OVER (ORDER BY SUM(f.total_amount) DESC) AS row_num,
        RANK()       OVER (ORDER BY SUM(f.total_amount) DESC) AS rank_pos,
        DENSE_RANK() OVER (ORDER BY SUM(f.total_amount) DESC) AS dense_rank_pos
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.product_key, p.product_name, p.category
ORDER BY revenue DESC;

-- 2.2 Top product inside each category (PARTITION BY)
SELECT category, product_name, revenue, rank_in_category
FROM (
    SELECT  p.category, p.product_name,
            SUM(f.total_amount) AS revenue,
            RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.total_amount) DESC) AS rank_in_category
    FROM fact_sales f
    JOIN dim_product p ON f.product_key = p.product_key
    GROUP BY p.category, p.product_key, p.product_name
) ranked
WHERE rank_in_category = 1
ORDER BY revenue DESC;

-- 2.3 Customer ranking within each store region
SELECT  s.region, c.customer_name, c.segment,
        SUM(f.total_amount) AS total_spent,
        DENSE_RANK() OVER (PARTITION BY s.region ORDER BY SUM(f.total_amount) DESC) AS region_rank
FROM fact_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_store    s ON f.store_key    = s.store_key
GROUP BY s.region, c.customer_key, c.customer_name, c.segment
ORDER BY s.region, region_rank;

-- 2.4 Customer quartiles with NTILE (1 = top spenders)
SELECT  c.customer_name,
        SUM(f.total_amount) AS total_spent,
        NTILE(4) OVER (ORDER BY SUM(f.total_amount) DESC) AS spend_quartile
FROM fact_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.customer_key, c.customer_name
ORDER BY total_spent DESC;

-- 2.5 Running total + LAG/LEAD of daily revenue (first 10 sale days)
WITH daily AS (
    SELECT d.full_date, SUM(f.total_amount) AS day_revenue
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.full_date
)
SELECT  full_date, day_revenue,
        SUM(day_revenue) OVER (ORDER BY full_date) AS running_total,
        LAG(day_revenue)  OVER (ORDER BY full_date) AS prev_day_revenue,
        LEAD(day_revenue) OVER (ORDER BY full_date) AS next_day_revenue
FROM daily
ORDER BY full_date
LIMIT 10;

-- =====================================================
-- REPORT 3: CTE-BASED MONTH-OVER-MONTH (MoM) GROWTH
-- =====================================================
WITH monthly AS (
    SELECT  d.year_num, d.month_num, d.month_name,
            SUM(f.total_amount)         AS revenue,
            COUNT(DISTINCT f.order_id)  AS orders
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year_num, d.month_num, d.month_name
),
with_prev AS (
    SELECT  *,
            LAG(revenue) OVER (ORDER BY year_num, month_num) AS prev_revenue
    FROM monthly
)
SELECT  year_num, month_name, orders, revenue,
        COALESCE(prev_revenue, 0)                          AS prev_revenue,
        COALESCE(revenue - prev_revenue, 0)                AS mom_change,
        COALESCE(ROUND((revenue - prev_revenue) * 100.0 / prev_revenue, 2), 0) AS mom_pct,
        CASE WHEN prev_revenue IS NULL      THEN 'Baseline'
             WHEN revenue > prev_revenue    THEN 'Growth'
             WHEN revenue < prev_revenue    THEN 'Decline'
             ELSE 'Flat' END                               AS trend
FROM with_prev
ORDER BY year_num, month_num;

-- =====================================================
-- REPORT 4: ROLLUP  (region -> category subtotals + grand total)
-- MySQL syntax: GROUP BY ... WITH ROLLUP ; GROUPING() marks subtotal rows
-- =====================================================
SELECT  CASE WHEN g_region = 1 THEN '** GRAND TOTAL **' ELSE region END AS region_label,
        CASE WHEN g_region = 1 THEN ''
             WHEN g_cat    = 1 THEN '-- Region Subtotal --' ELSE category END AS category_label,
        units_sold, revenue
FROM (
    SELECT  s.region, p.category,
            GROUPING(s.region)   AS g_region,
            GROUPING(p.category) AS g_cat,
            SUM(f.quantity)      AS units_sold,
            SUM(f.total_amount)  AS revenue
    FROM fact_sales f
    JOIN dim_store   s ON f.store_key   = s.store_key
    JOIN dim_product p ON f.product_key = p.product_key
    GROUP BY s.region, p.category WITH ROLLUP
) r
ORDER BY g_region, region, g_cat, category;

-- =====================================================
-- REPORT 5: QUERY OPTIMISATION WITH EXPLAIN
-- =====================================================

-- 5.1 Star-join query: check the plan (look at 'type' and 'key' columns)
EXPLAIN
SELECT  d.month_name, p.category, SUM(f.total_amount) AS revenue
FROM fact_sales f
JOIN dim_date    d ON f.date_key    = d.date_key
JOIN dim_product p ON f.product_key = p.product_key
JOIN dim_store   s ON f.store_key   = s.store_key
WHERE d.year_num = 2026 AND s.region = 'South'
GROUP BY d.month_name, p.category;

-- 5.2 Before / after an index on a non-key lookup column
EXPLAIN SELECT * FROM fact_sales WHERE order_id = 'ORD-1050';   -- BEFORE: type = ALL (full scan)

CREATE INDEX idx_fact_order ON fact_sales(order_id);

EXPLAIN SELECT * FROM fact_sales WHERE order_id = 'ORD-1050';   -- AFTER : type = ref, key = idx_fact_order

-- Optional (MySQL 8.0.18+): real timings
EXPLAIN ANALYZE SELECT * FROM fact_sales WHERE order_id = 'ORD-1050';
