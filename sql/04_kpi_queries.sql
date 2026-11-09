/* KPI queries. Each one matches a KPI in docs/requirements.md, and the
   expected results are in docs/test_cases.md. Run these before building
   the Power BI report so you have numbers to reconcile against. */

USE OTC_Portfolio;
GO
DECLARE @AsOf DATE = '2025-12-31';

-- KPI-01  Net billed revenue by month
SELECT  FORMAT(INVOICE_DATE, 'yyyy-MM') AS billing_month,
        COUNT(DISTINCT INVOICE)         AS invoices,
        SUM(NET_REVENUE)                AS net_revenue
FROM    otc.vw_FactBilling
GROUP BY FORMAT(INVOICE_DATE, 'yyyy-MM')
ORDER BY billing_month;

-- KPI-02  Order-to-invoice cycle time (days), by order month
--         Order level: order date to the last valid invoice for that order.
WITH o AS (
    SELECT SALES_ORDER, ORDER_DATE, MAX(INVOICE_DATE) AS last_invoice
    FROM   otc.vw_OTC_ItemFlow
    WHERE  INVOICE_DATE IS NOT NULL
    GROUP BY SALES_ORDER, ORDER_DATE
)
SELECT  FORMAT(ORDER_DATE, 'yyyy-MM')                                    AS order_month,
        COUNT(*)                                                         AS invoiced_orders,
        CAST(AVG(CAST(DATEDIFF(DAY, ORDER_DATE, last_invoice) AS DECIMAL(9,2))) AS DECIMAL(9,1)) AS avg_days
FROM    o
GROUP BY FORMAT(ORDER_DATE, 'yyyy-MM')
ORDER BY order_month;

-- KPI-03  On-time delivery % (goods issue on or before requested date), delivery level
SELECT  COUNT(*) AS shipped_deliveries,
        SUM(CASE WHEN WADAT_IST <= LFDAT THEN 1 ELSE 0 END) AS on_time,
        CAST(100.0 * SUM(CASE WHEN WADAT_IST <= LFDAT THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS on_time_pct
FROM    otc.LIKP
WHERE   WADAT_IST IS NOT NULL;

-- KPI-04  Orders on credit block, with value and age
SELECT  ak.VBELN AS sales_order, ak.ERDAT AS order_date, c.NAME1 AS customer,
        cr.RISK_CLASS, ak.NETWR AS order_value,
        DATEDIFF(DAY, ak.ERDAT, @AsOf) AS days_blocked
FROM    otc.VBAK ak
JOIN    otc.KNA1 c             ON c.KUNNR = ak.KUNNR
JOIN    otc.CUSTOMER_CREDIT cr ON cr.KUNNR = ak.KUNNR
WHERE   ak.CMGST = 'B'
ORDER BY days_blocked DESC;

-- KPI-05  Average credit release time (orders blocked and then released)
SELECT  COUNT(*) AS released_orders,
        CAST(AVG(CAST(DATEDIFF(DAY, ERDAT, CREDIT_RELEASE_DATE) AS DECIMAL(9,2))) AS DECIMAL(9,1)) AS avg_days_to_release
FROM    otc.VBAK
WHERE   CMGST = 'D';

-- KPI-06  Backorders: unconfirmed quantity and value by material
SELECT  f.MATERIAL, m.MAKTX,
        COUNT(*)              AS items_short,
        SUM(f.BACKORDER_QTY)  AS backorder_qty,
        SUM(f.BACKORDER_VALUE) AS backorder_value
FROM    otc.vw_OTC_ItemFlow f
JOIN    otc.MARA m ON m.MATNR = f.MATERIAL
WHERE   f.BACKORDER_QTY > 0
GROUP BY f.MATERIAL, m.MAKTX
ORDER BY backorder_value DESC;

-- KPI-07  Delivered not billed (goods issued, no valid invoice), with aging buckets
SELECT  CASE WHEN DATEDIFF(DAY, GI_DATE, @AsOf) <= 3 THEN '0-3 days'
             WHEN DATEDIFF(DAY, GI_DATE, @AsOf) <= 7 THEN '4-7 days'
             ELSE '8+ days' END                 AS aging_bucket,
        COUNT(DISTINCT SALES_ORDER)             AS orders,
        SUM(GI_QTY * NET_PRICE)                 AS unbilled_value
FROM    otc.vw_OTC_ItemFlow
WHERE   GI_DATE IS NOT NULL AND INVOICE IS NULL
GROUP BY CASE WHEN DATEDIFF(DAY, GI_DATE, @AsOf) <= 3 THEN '0-3 days'
              WHEN DATEDIFF(DAY, GI_DATE, @AsOf) <= 7 THEN '4-7 days'
              ELSE '8+ days' END
ORDER BY aging_bucket;

-- KPI-08  Fill rate: confirmed qty / ordered qty, rejected items excluded
SELECT  SUM(CONFIRMED_QTY) AS confirmed_qty,
        SUM(ORDER_QTY)     AS ordered_qty,
        CAST(100.0 * SUM(CONFIRMED_QTY) / SUM(ORDER_QTY) AS DECIMAL(5,1)) AS fill_rate_pct
FROM    otc.vw_OTC_ItemFlow
WHERE   IS_REJECTED = 0;

-- KPI-09  Item status snapshot (feeds the pipeline visual)
SELECT  ITEM_STATUS, COUNT(*) AS items, SUM(ORDER_VALUE) AS order_value
FROM    otc.vw_OTC_ItemFlow
GROUP BY ITEM_STATUS
ORDER BY items DESC;

-- KPI-10  Top customers by net revenue, with credit utilization
--         Open exposure here = open order value + delivered not billed (simplified, no open AR).
WITH rev AS (
    SELECT CUSTOMER, SUM(NET_REVENUE) AS net_revenue FROM otc.vw_FactBilling GROUP BY CUSTOMER
), exposure AS (
    SELECT CUSTOMER,
           SUM(CASE WHEN ITEM_STATUS IN ('Open Order','Backordered','In Shipping','Credit Block','Delivery Block')
                    THEN ORDER_VALUE ELSE 0 END)
         + SUM(CASE WHEN ITEM_STATUS = 'Delivered Not Billed' THEN GI_QTY * NET_PRICE ELSE 0 END) AS open_exposure
    FROM otc.vw_OTC_ItemFlow
    GROUP BY CUSTOMER
)
SELECT  d.CUSTOMER_NAME, d.REGION, d.RISK_CLASS, r.net_revenue, e.open_exposure, d.CREDIT_LIMIT,
        CAST(100.0 * e.open_exposure / d.CREDIT_LIMIT AS DECIMAL(5,1)) AS credit_used_pct
FROM    otc.vw_DimCustomer d
JOIN    rev r      ON r.CUSTOMER = d.CUSTOMER
JOIN    exposure e ON e.CUSTOMER = d.CUSTOMER
ORDER BY r.net_revenue DESC;

-- DQ-01  Data quality checks. Every row should return 0.
SELECT 'Delivery item without sales order item' AS check_name, COUNT(*) AS failures
FROM   otc.LIPS ps LEFT JOIN otc.VBAP ap ON ap.VBELN = ps.VGBEL AND ap.POSNR = ps.VGPOS
WHERE  ap.VBELN IS NULL
UNION ALL
SELECT 'Billed qty above delivered qty', COUNT(*)
FROM   otc.vw_OTC_ItemFlow WHERE BILLED_QTY > GI_QTY
UNION ALL
SELECT 'Invoice dated before goods issue', COUNT(*)
FROM   otc.vw_OTC_ItemFlow WHERE INVOICE_DATE < GI_DATE
UNION ALL
SELECT 'Credit-blocked order with a delivery', COUNT(*)
FROM   otc.vw_OTC_ItemFlow WHERE CREDIT_STATUS = 'B' AND DELIVERY IS NOT NULL
UNION ALL
SELECT 'Header value not equal to sum of open items', COUNT(*)
FROM   otc.VBAK ak
JOIN  (SELECT VBELN, SUM(NETWR) AS s FROM otc.VBAP WHERE ABGRU IS NULL GROUP BY VBELN) i ON i.VBELN = ak.VBELN
WHERE  ABS(ak.NETWR - i.s) > 0.01
UNION ALL
SELECT 'Cancellation (S1) pointing to a non-cancelled invoice', COUNT(*)
FROM   otc.VBRK s JOIN otc.VBRK o ON o.VBELN = s.SFAKN
WHERE  s.FKART = 'S1' AND ISNULL(o.FKSTO, '') <> 'X';
GO
