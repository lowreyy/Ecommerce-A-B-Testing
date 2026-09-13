-- =========================================================
-- A/B TEST ANALYSIS: Control vs Variant_A vs Variant_B
-- Marketing & E-Commerce Analytics Dataset
--
-- IMPORTANT DATA NOTE:
-- experiment_group is assigned at the EVENT/VISIT level, not the
-- customer level -- 99,963 of 100,000 customers appear under more
-- than one experiment_group across their events. Treat this as a
-- visit-level (impression-level) experiment: each row in `events`
-- is one independently randomized visit/interaction. Do NOT
-- aggregate metrics "per customer" and compare across groups, since
-- most customers were exposed to multiple variants.
-- =========================================================


-- =========================================================
-- SECTION 1: Experiment overview / sample sizes (Sample Ratio Mismatch check)
-- =========================================================
-- Confirms group sizes are roughly as expected (Control ~60%, A ~20%, B ~20%).
-- A skewed split here would be a red flag (Sample Ratio Mismatch) worth
-- flagging before trusting any downstream result.
SELECT
    experiment_group,
    COUNT(*)                                            AS total_events,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_total
FROM events
GROUP BY experiment_group
ORDER BY experiment_group;


-- =========================================================
-- SECTION 2: Primary metric -- conversion rate by group
-- =========================================================
-- Conversion = purchase events / total events (visits) in that group.
-- This output (group, trials, successes, rate) is exactly the input
-- you need for a two-proportion z-test / chi-square test in Python.
SELECT
    experiment_group,
    COUNT(*)                                                   AS n_visits,
    COUNT(*) FILTER (WHERE event_type = 'purchase')            AS n_purchases,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE event_type = 'purchase') / COUNT(*),
        3
    )                                                            AS conversion_rate_pct
FROM events
GROUP BY experiment_group
ORDER BY experiment_group;


-- =========================================================
-- SECTION 3: Funnel breakdown by group
-- =========================================================
-- Shows where each group drops off: Home/PLP/PDP -> Cart -> Checkout -> Purchase.
-- Great for a funnel chart in the dashboard.
SELECT
    experiment_group,
    COUNT(*) FILTER (WHERE page_category = 'Home')               AS home_visits,
    COUNT(*) FILTER (WHERE page_category = 'PLP')                AS plp_visits,
    COUNT(*) FILTER (WHERE page_category = 'PDP')                AS pdp_visits,
    COUNT(*) FILTER (WHERE page_category = 'Cart')                AS cart_visits,
    COUNT(*) FILTER (WHERE page_category = 'Checkout')            AS checkout_visits,
    COUNT(*) FILTER (WHERE event_type = 'purchase')               AS purchases,
    COUNT(*) FILTER (WHERE event_type = 'bounce')                 AS bounces,
    ROUND(100.0 * COUNT(*) FILTER (WHERE event_type = 'bounce') / COUNT(*), 2) AS bounce_rate_pct
FROM events
GROUP BY experiment_group
ORDER BY experiment_group;


-- Step-over-step funnel conversion (Cart -> Checkout -> Purchase), as ratios
WITH funnel AS (
    SELECT
        experiment_group,
        COUNT(*) FILTER (WHERE page_category = 'Cart')      AS cart_visits,
        COUNT(*) FILTER (WHERE page_category = 'Checkout')  AS checkout_visits,
        COUNT(*) FILTER (WHERE event_type = 'purchase')     AS purchases
    FROM events
    GROUP BY experiment_group
)
SELECT
    experiment_group,
    cart_visits,
    checkout_visits,
    purchases,
    ROUND(100.0 * checkout_visits / NULLIF(cart_visits, 0), 2)   AS cart_to_checkout_pct,
    ROUND(100.0 * purchases / NULLIF(checkout_visits, 0), 2)     AS checkout_to_purchase_pct
FROM funnel
ORDER BY experiment_group;


-- =========================================================
-- SECTION 4: Segment cuts -- does the lift hold everywhere?
-- (Checking for Simpson's paradox / segment-level reversals)
-- =========================================================

-- 4a. By device type
SELECT
    device_type,
    experiment_group,
    COUNT(*)                                                AS n_visits,
    COUNT(*) FILTER (WHERE event_type = 'purchase')         AS n_purchases,
    ROUND(100.0 * COUNT(*) FILTER (WHERE event_type = 'purchase') / COUNT(*), 3) AS conversion_rate_pct
FROM events
GROUP BY device_type, experiment_group
ORDER BY device_type, experiment_group;

-- 4b. By traffic source (normalize casing inconsistency from source data)
SELECT
    INITCAP(traffic_source)                                 AS traffic_source_clean,
    experiment_group,
    COUNT(*)                                                AS n_visits,
    COUNT(*) FILTER (WHERE event_type = 'purchase')         AS n_purchases,
    ROUND(100.0 * COUNT(*) FILTER (WHERE event_type = 'purchase') / COUNT(*), 3) AS conversion_rate_pct
FROM events
GROUP BY INITCAP(traffic_source), experiment_group
ORDER BY traffic_source_clean, experiment_group;

-- 4c. By customer country (join to customers)
SELECT
    c.country,
    e.experiment_group,
    COUNT(*)                                                AS n_visits,
    COUNT(*) FILTER (WHERE e.event_type = 'purchase')       AS n_purchases,
    ROUND(100.0 * COUNT(*) FILTER (WHERE e.event_type = 'purchase') / COUNT(*), 3) AS conversion_rate_pct
FROM events e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY c.country, e.experiment_group
ORDER BY c.country, e.experiment_group;

-- 4d. By loyalty tier (join to customers)
SELECT
    c.loyalty_tier,
    e.experiment_group,
    COUNT(*)                                                AS n_visits,
    COUNT(*) FILTER (WHERE e.event_type = 'purchase')       AS n_purchases,
    ROUND(100.0 * COUNT(*) FILTER (WHERE e.event_type = 'purchase') / COUNT(*), 3) AS conversion_rate_pct
FROM events e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY c.loyalty_tier, e.experiment_group
ORDER BY c.loyalty_tier, e.experiment_group;


-- =========================================================
-- SECTION 5: Revenue & guardrail metrics
-- Join purchase events -> transactions 1:1 on (customer_id, timestamp)
-- to attach revenue/refund data to each experiment group.
-- =========================================================
WITH purchase_revenue AS (
    SELECT
        e.experiment_group,
        t.transaction_id,
        t.gross_revenue,
        t.refund_flag,
        t.quantity
    FROM events e
    JOIN transactions t
        ON t.customer_id = e.customer_id
       AND t.timestamp   = e.timestamp
    WHERE e.event_type = 'purchase'
)
SELECT
    experiment_group,
    COUNT(*)                                                    AS n_orders,
    ROUND(SUM(gross_revenue)::numeric, 2)                       AS total_revenue,
    ROUND(AVG(gross_revenue)::numeric, 2)                       AS avg_order_value,
    COUNT(*) FILTER (WHERE refund_flag)                         AS n_refunds,
    ROUND(100.0 * COUNT(*) FILTER (WHERE refund_flag) / COUNT(*), 2) AS refund_rate_pct
FROM purchase_revenue
GROUP BY experiment_group
ORDER BY experiment_group;


-- Revenue per visit (RPV) by group -- blends conversion rate + AOV into one
-- guardrail-friendly metric: total revenue generated per 100 visits.
WITH purchase_revenue AS (
    SELECT
        e.experiment_group,
        t.gross_revenue
    FROM events e
    JOIN transactions t
        ON t.customer_id = e.customer_id
       AND t.timestamp   = e.timestamp
    WHERE e.event_type = 'purchase'
),
visits AS (
    SELECT experiment_group, COUNT(*) AS n_visits
    FROM events
    GROUP BY experiment_group
)
SELECT
    v.experiment_group,
    v.n_visits,
    ROUND(COALESCE(SUM(pr.gross_revenue), 0)::numeric, 2)              AS total_revenue,
    ROUND(COALESCE(SUM(pr.gross_revenue), 0) / v.n_visits, 4)          AS revenue_per_visit,
    ROUND(100.0 * COALESCE(SUM(pr.gross_revenue), 0) / v.n_visits, 2)  AS revenue_per_100_visits
FROM visits v
LEFT JOIN purchase_revenue pr ON pr.experiment_group = v.experiment_group
GROUP BY v.experiment_group, v.n_visits
ORDER BY v.experiment_group;


-- =========================================================
-- SECTION 6: Revenue impact projection
-- "If we rolled the winning variant out to all Control traffic,
-- what's the estimated revenue lift?"
-- =========================================================
WITH purchase_revenue AS (
    SELECT
        e.experiment_group,
        t.gross_revenue
    FROM events e
    JOIN transactions t
        ON t.customer_id = e.customer_id
       AND t.timestamp   = e.timestamp
    WHERE e.event_type = 'purchase'
),
group_stats AS (
    SELECT
        v.experiment_group,
        v.n_visits,
        COALESCE(SUM(pr.gross_revenue), 0) / v.n_visits AS revenue_per_visit
    FROM (SELECT experiment_group, COUNT(*) AS n_visits FROM events GROUP BY experiment_group) v
    LEFT JOIN purchase_revenue pr ON pr.experiment_group = v.experiment_group
    GROUP BY v.experiment_group, v.n_visits
),
control AS (
    SELECT n_visits AS control_visits, revenue_per_visit AS control_rpv
    FROM group_stats WHERE experiment_group = 'Control'
)
SELECT
    gs.experiment_group,
    ROUND(gs.revenue_per_visit::numeric, 4)                                   AS revenue_per_visit,
    ROUND((gs.revenue_per_visit - c.control_rpv)::numeric, 4)                 AS uplift_per_visit_vs_control,
    ROUND((c.control_visits * (gs.revenue_per_visit - c.control_rpv))::numeric, 2)
                                                                                 AS projected_incremental_revenue_if_rolled_out_to_control_traffic
FROM group_stats gs
CROSS JOIN control c
WHERE gs.experiment_group <> 'Control'
ORDER BY gs.experiment_group;
