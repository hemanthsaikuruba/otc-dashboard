/* Reporting views for Power BI.
   vw_OTC_ItemFlow gives one row per sales order item and follows it through
   delivery and billing, the same chain you see in VA03 document flow. */

USE OTC_Portfolio;
GO

CREATE OR ALTER VIEW otc.vw_OTC_ItemFlow AS
WITH dlv AS (
    SELECT  ps.VGBEL, ps.VGPOS,
            MIN(lk.VBELN)      AS DELIVERY,
            MIN(lk.ERDAT)      AS DELIVERY_CREATED,
            MAX(lk.WADAT_IST)  AS GI_DATE,
            SUM(ps.LFIMG)      AS DELIVERY_QTY,
            SUM(CASE WHEN lk.WADAT_IST IS NOT NULL THEN ps.LFIMG ELSE 0 END) AS GI_QTY
    FROM    otc.LIPS ps
    JOIN    otc.LIKP lk ON lk.VBELN = ps.VBELN
    GROUP BY ps.VGBEL, ps.VGPOS
),
bil AS (   -- valid invoices only: F2 that has not been cancelled
    SELECT  rp.AUBEL, rp.AUPOS,
            MAX(rk.VBELN)  AS INVOICE,
            MAX(rk.FKDAT)  AS INVOICE_DATE,
            SUM(rp.FKIMG)  AS BILLED_QTY,
            SUM(rp.NETWR)  AS BILLED_VALUE
    FROM    otc.VBRP rp
    JOIN    otc.VBRK rk ON rk.VBELN = rp.VBELN
    WHERE   rk.FKART = 'F2' AND rk.FKSTO IS NULL
    GROUP BY rp.AUBEL, rp.AUPOS
)
SELECT
    ak.VBELN                    AS SALES_ORDER,
    ap.POSNR                    AS ITEM,
    ak.ERDAT                    AS ORDER_DATE,
    ak.KUNNR                    AS CUSTOMER,
    ap.MATNR                    AS MATERIAL,
    ap.KWMENG                   AS ORDER_QTY,
    ep.BMENG                    AS CONFIRMED_QTY,
    ap.NETPR                    AS NET_PRICE,
    ap.NETWR                    AS ORDER_VALUE,
    CASE WHEN ap.ABGRU IS NOT NULL THEN 1 ELSE 0 END AS IS_REJECTED,
    ak.CMGST                    AS CREDIT_STATUS,
    ak.CREDIT_RELEASE_DATE,
    ak.LIFSK                    AS DELIVERY_BLOCK,
    ak.FAKSK                    AS BILLING_BLOCK,
    ep.EDATU                    AS REQUESTED_DATE,
    d.DELIVERY, d.DELIVERY_CREATED, d.GI_DATE,
    ISNULL(d.DELIVERY_QTY, 0)   AS DELIVERY_QTY,
    ISNULL(d.GI_QTY, 0)         AS GI_QTY,
    b.INVOICE, b.INVOICE_DATE,
    ISNULL(b.BILLED_QTY, 0)     AS BILLED_QTY,
    ISNULL(b.BILLED_VALUE, 0)   AS BILLED_VALUE,
    CASE WHEN ap.ABGRU IS NULL THEN ep.WMENG - ep.BMENG ELSE 0 END             AS BACKORDER_QTY,
    CASE WHEN ap.ABGRU IS NULL THEN (ep.WMENG - ep.BMENG) * ap.NETPR ELSE 0 END AS BACKORDER_VALUE,
    CASE WHEN d.GI_DATE IS NOT NULL THEN
         CASE WHEN d.GI_DATE <= ep.EDATU THEN 1 ELSE 0 END END                 AS IS_ON_TIME,
    CASE WHEN d.GI_DATE IS NOT NULL THEN DATEDIFF(DAY, ep.EDATU, d.GI_DATE) END AS DAYS_LATE,
    CASE WHEN b.INVOICE_DATE IS NOT NULL THEN DATEDIFF(DAY, ak.ERDAT, b.INVOICE_DATE) END AS ORDER_TO_INVOICE_DAYS,
    CASE
        WHEN ap.ABGRU IS NOT NULL       THEN 'Rejected'
        WHEN ak.CMGST = 'B'             THEN 'Credit Block'
        WHEN ak.LIFSK IS NOT NULL       THEN 'Delivery Block'
        WHEN b.INVOICE IS NOT NULL      THEN 'Billed'
        WHEN d.GI_DATE IS NOT NULL      THEN 'Delivered Not Billed'
        WHEN d.DELIVERY IS NOT NULL     THEN 'In Shipping'
        WHEN ep.BMENG = 0               THEN 'Backordered'
        ELSE 'Open Order'
    END AS ITEM_STATUS
FROM    otc.VBAP ap
JOIN    otc.VBAK ak ON ak.VBELN = ap.VBELN
JOIN    otc.VBEP ep ON ep.VBELN = ap.VBELN AND ep.POSNR = ap.POSNR AND ep.ETENR = '0001'
LEFT JOIN dlv d ON d.VGBEL = ap.VBELN AND d.VGPOS = ap.POSNR
LEFT JOIN bil b ON b.AUBEL = ap.VBELN AND b.AUPOS = ap.POSNR;
GO

-- Customer dimension with credit data
CREATE OR ALTER VIEW otc.vw_DimCustomer AS
SELECT  c.KUNNR AS CUSTOMER, c.NAME1 AS CUSTOMER_NAME, c.ORT01 AS CITY, c.REGIO AS STATE,
        c.REGION, c.KTOKD AS ACCOUNT_GROUP, cr.CREDIT_LIMIT, cr.RISK_CLASS
FROM    otc.KNA1 c
LEFT JOIN otc.CUSTOMER_CREDIT cr ON cr.KUNNR = c.KUNNR;
GO

-- Material dimension
CREATE OR ALTER VIEW otc.vw_DimMaterial AS
SELECT  MATNR AS MATERIAL, MAKTX AS MATERIAL_DESC, MATKL AS MATERIAL_GROUP, MEINS AS BASE_UOM, LIST_PRICE
FROM    otc.MARA;
GO

-- Billing at document level, cancellations excluded
CREATE OR ALTER VIEW otc.vw_FactBilling AS
SELECT  rk.VBELN AS INVOICE, rk.FKDAT AS INVOICE_DATE, rk.KUNRG AS CUSTOMER,
        rp.POSNR AS INVOICE_ITEM, rp.MATNR AS MATERIAL, rp.FKIMG AS BILLED_QTY,
        rp.NETWR AS NET_REVENUE, rp.AUBEL AS SALES_ORDER
FROM    otc.VBRK rk
JOIN    otc.VBRP rp ON rp.VBELN = rk.VBELN
WHERE   rk.FKART = 'F2' AND rk.FKSTO IS NULL;
GO
