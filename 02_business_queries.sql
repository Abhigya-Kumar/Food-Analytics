/* =====================================================================
   ZOMATO SALES ANALYSIS - BUSINESS QUERIES
   =====================================================================
   Written for MySQL 8+ / PostgreSQL 12+ (PostgreSQL equivalents noted
   where syntax differs, e.g. DATE_FORMAT -> TO_CHAR).
   All figures validated against the provided dataset (SQLite test run).

   SECTIONS
     A. KPI Overview
     B. Revenue & Trend Analysis
     C. City & Cuisine Analysis
     D. Restaurant Performance
     E. Customer Analysis (incl. RFM segmentation)
     F. Payments & Discounts
   ===================================================================== */


/* =====================================================================
   SECTION A — KPI OVERVIEW
   ===================================================================== */

-- A1. Headline business KPIs: orders, revenue, AOV, cancellation rate
SELECT
    COUNT(*)                                                          AS total_orders,
    SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END)       AS delivered_orders,
    SUM(CASE WHEN order_status LIKE 'Cancelled%' THEN 1 ELSE 0 END)   AS cancelled_orders,
    ROUND(SUM(CASE WHEN order_status = 'Delivered'
                    THEN total_amount ELSE 0 END), 2)                 AS total_revenue,
    ROUND(SUM(CASE WHEN order_status = 'Delivered' THEN total_amount ELSE 0 END)
          / NULLIF(SUM(CASE WHEN order_status = 'Delivered' THEN 1 ELSE 0 END), 0), 2)
                                                                        AS avg_order_value,
    ROUND(100.0 * SUM(CASE WHEN order_status LIKE 'Cancelled%' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                              AS cancellation_rate_pct
FROM orders;


/* =====================================================================
   SECTION B — REVENUE & TREND ANALYSIS
   ===================================================================== */

-- B1. Monthly revenue & order volume trend
SELECT
    DATE_FORMAT(order_datetime, '%Y-%m')   AS order_month,     -- PostgreSQL: TO_CHAR(order_datetime,'YYYY-MM')
    COUNT(*)                                AS orders,
    ROUND(SUM(total_amount), 2)             AS revenue
FROM orders
WHERE order_status = 'Delivered'
GROUP BY order_month
ORDER BY order_month;

-- B2. Month-over-month revenue growth % (window function: LAG)
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(order_datetime, '%Y-%m') AS order_month,
        SUM(total_amount)                     AS revenue
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2)                                                     AS revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
          / LAG(revenue) OVER (ORDER BY order_month), 2)                  AS mom_growth_pct
FROM monthly_revenue
ORDER BY order_month;

-- B3. Running (cumulative) revenue total by month — window function: SUM() OVER
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(order_datetime, '%Y-%m') AS order_month,
        SUM(total_amount)                     AS revenue
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY order_month), 2) AS cumulative_revenue
FROM monthly_revenue
ORDER BY order_month;

-- B4. Revenue by day of week (which day drives the most business?)
SELECT
    DAYNAME(order_datetime)              AS day_of_week,       -- PostgreSQL: TO_CHAR(order_datetime,'Day')
    COUNT(*)                              AS orders,
    ROUND(SUM(total_amount), 2)           AS revenue,
    ROUND(AVG(total_amount), 2)           AS avg_order_value
FROM orders
WHERE order_status = 'Delivered'
GROUP BY day_of_week
ORDER BY revenue DESC;

-- B5. Peak ordering hours (lunch vs. dinner vs. other)
SELECT
    HOUR(order_datetime)                  AS order_hour,
    COUNT(*)                              AS orders,
    ROUND(SUM(total_amount), 2)           AS revenue
FROM orders
WHERE order_status = 'Delivered'
GROUP BY order_hour
ORDER BY order_hour;


/* =====================================================================
   SECTION C — CITY & CUISINE ANALYSIS
   ===================================================================== */

-- C1. Revenue and order volume by city
SELECT
    r.city,
    COUNT(*)                             AS orders,
    ROUND(SUM(o.total_amount), 2)        AS revenue,
    ROUND(AVG(o.total_amount), 2)        AS avg_order_value
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY r.city
ORDER BY revenue DESC;

-- C2. Cuisine-wise performance: orders, revenue, AOV, avg customer rating
SELECT
    r.cuisine,
    COUNT(*)                             AS orders,
    ROUND(SUM(o.total_amount), 2)        AS revenue,
    ROUND(AVG(o.total_amount), 2)        AS avg_order_value,
    ROUND(AVG(o.customer_rating), 2)     AS avg_rating
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY r.cuisine
ORDER BY revenue DESC;

-- C3. City-wise average delivery time & cancellation rate (operational health)
SELECT
    r.city,
    ROUND(AVG(CASE WHEN o.order_status = 'Delivered'
               THEN o.delivery_time_mins END), 1)                       AS avg_delivery_time_mins,
    ROUND(100.0 * SUM(CASE WHEN o.order_status LIKE 'Cancelled%' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                AS cancellation_rate_pct
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
GROUP BY r.city
ORDER BY cancellation_rate_pct DESC;


/* =====================================================================
   SECTION D — RESTAURANT PERFORMANCE
   ===================================================================== */

-- D1. Top 10 restaurants by revenue
SELECT
    r.restaurant_name, r.city, r.cuisine,
    COUNT(*)                             AS orders,
    ROUND(SUM(o.total_amount), 2)        AS revenue
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered'
GROUP BY r.restaurant_id
ORDER BY revenue DESC
LIMIT 10;

-- D2. Top-rated restaurants with a meaningful order volume (HAVING filter)
SELECT
    r.restaurant_name, r.city,
    COUNT(*)                             AS orders,
    ROUND(AVG(o.customer_rating), 2)     AS avg_customer_rating
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
WHERE o.order_status = 'Delivered' AND o.customer_rating IS NOT NULL
GROUP BY r.restaurant_id
HAVING COUNT(*) >= 30
ORDER BY avg_customer_rating DESC
LIMIT 10;

-- D3. Rank restaurants WITHIN each city by revenue (window function: RANK),
--     then keep only the top 3 per city via an outer filter on the ranked result
WITH restaurant_revenue AS (
    SELECT
        r.restaurant_id, r.restaurant_name, r.city,
        SUM(o.total_amount) AS revenue
    FROM orders o
    JOIN restaurants r ON o.restaurant_id = r.restaurant_id
    WHERE o.order_status = 'Delivered'
    GROUP BY r.restaurant_id
),
ranked AS (
    SELECT
        city, restaurant_name, ROUND(revenue, 2) AS revenue,
        RANK() OVER (PARTITION BY city ORDER BY revenue DESC) AS city_rank
    FROM restaurant_revenue
)
SELECT city, restaurant_name, revenue, city_rank
FROM ranked
WHERE city_rank <= 3
ORDER BY city, city_rank;

-- D4. Restaurants with the highest cancellation rate (min. 20 orders, quality-control flag)
SELECT
    r.restaurant_name, r.city,
    COUNT(*)                                                            AS total_orders,
    SUM(CASE WHEN o.order_status LIKE 'Cancelled%' THEN 1 ELSE 0 END)   AS cancelled_orders,
    ROUND(100.0 * SUM(CASE WHEN o.order_status LIKE 'Cancelled%' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                AS cancellation_rate_pct
FROM orders o
JOIN restaurants r ON o.restaurant_id = r.restaurant_id
GROUP BY r.restaurant_id
HAVING COUNT(*) >= 20
ORDER BY cancellation_rate_pct DESC
LIMIT 10;


/* =====================================================================
   SECTION E — CUSTOMER ANALYSIS
   ===================================================================== */

-- E1. Top 10 customers by lifetime spend (Customer Lifetime Value)
SELECT
    c.customer_id, c.customer_name, c.city,
    COUNT(*)                          AS total_orders,
    ROUND(SUM(o.total_amount), 2)     AS lifetime_spend
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'Delivered'
GROUP BY c.customer_id
ORDER BY lifetime_spend DESC
LIMIT 10;

-- E2. Repeat vs. one-time customers — orders & revenue contribution
WITH customer_orders AS (
    SELECT customer_id, COUNT(*) AS order_count, SUM(total_amount) AS spend
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    CASE WHEN order_count = 1 THEN 'One-time customer' ELSE 'Repeat customer' END AS customer_type,
    COUNT(*)                       AS num_customers,
    SUM(order_count)               AS total_orders,
    ROUND(SUM(spend), 2)           AS total_revenue,
    ROUND(100.0 * SUM(spend) / SUM(SUM(spend)) OVER (), 2) AS pct_of_total_revenue
FROM customer_orders
GROUP BY customer_type;

-- E3. Premium (Gold) vs. non-premium member comparison
SELECT
    c.is_premium_member,
    COUNT(DISTINCT c.customer_id)         AS customers,
    COUNT(o.order_id)                     AS orders,
    ROUND(AVG(o.total_amount), 2)         AS avg_order_value,
    ROUND(COUNT(o.order_id) * 1.0 / COUNT(DISTINCT c.customer_id), 2) AS avg_orders_per_customer
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'Delivered'
GROUP BY c.is_premium_member;

-- E4. RFM segmentation (Recency, Frequency, Monetary) — CTE + CASE-based scoring
WITH customer_rfm AS (
    SELECT
        c.customer_id, c.customer_name,
        DATEDIFF((SELECT MAX(order_datetime) FROM orders), MAX(o.order_datetime)) AS recency_days,
        COUNT(*)                     AS frequency,
        SUM(o.total_amount)          AS monetary
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'Delivered'
    GROUP BY c.customer_id
)
SELECT
    customer_id, customer_name, recency_days, frequency, ROUND(monetary, 2) AS monetary,
    CASE
        WHEN recency_days <= 30 AND frequency >= 5 THEN 'Champion'
        WHEN recency_days <= 60 AND frequency >= 3 THEN 'Loyal Customer'
        WHEN recency_days > 120                    THEN 'At Risk / Churned'
        ELSE 'Needs Attention'
    END AS rfm_segment
FROM customer_rfm
ORDER BY monetary DESC;


/* =====================================================================
   SECTION F — PAYMENTS & DISCOUNTS
   ===================================================================== */

-- F1. Payment method distribution (orders & revenue share)
SELECT
    payment_method,
    COUNT(*)                                                     AS orders,
    ROUND(SUM(total_amount), 2)                                  AS revenue,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)           AS pct_of_orders
FROM orders
WHERE order_status = 'Delivered'
GROUP BY payment_method
ORDER BY revenue DESC;

-- F2. Discount impact: do discounted orders drive a higher order value?
SELECT
    CASE WHEN discount_amount > 0 THEN 'Discounted Order' ELSE 'Full-Price Order' END AS order_type,
    COUNT(*)                             AS orders,
    ROUND(AVG(order_value), 2)           AS avg_order_value_pre_discount,
    ROUND(AVG(total_amount), 2)          AS avg_final_amount
FROM orders
WHERE order_status = 'Delivered'
GROUP BY order_type;
