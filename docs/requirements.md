# Business requirements: order-to-cash performance dashboard

Company: Northfield Lab Supply Co. (fictional)
Prepared by: Hemanthsai Kuruba, Business Systems Analyst
Version: 1.0
Data as of: 2025-12-31

## 1. Background

Northfield sells lab consumables, reagents and equipment to hospitals, research labs and distributors across the US. Orders are entered in SAP S/4HANA SD (sales org 1000, distribution channel 10, plant 1000).

Today the Customer Service, Credit and Billing teams each pull their own reports from VA05, VL06O, VF04 and SE16N, then combine them in Excel every Monday. It takes about half a day, the numbers often disagree between teams, and nobody can see where an order is stuck without opening VA03 document flow one order at a time.

## 2. Problem statement

The business has no single view of the order-to-cash flow. As a result:

1. Credit-blocked orders sit for weeks because no one owns the follow-up.
2. Backorders on short-supply materials are found when the customer calls, not before.
3. Goods that have shipped but are not billed delay revenue, and month-end close runs late.
4. Leadership cannot see order-to-invoice cycle time or on-time delivery by customer or region.

## 3. Objective

Give Customer Service, Credit, Billing and Sales leadership one Power BI report, refreshed daily from SAP SD data, that shows where every order item is in the flow and the KPIs below. Success means the Monday Excel process is retired and each team works its exceptions from the same numbers.

## 4. Stakeholders

| Role | Team | What they need |
|---|---|---|
| Customer Service Manager | Customer Service | Open orders, backorders, late deliveries by customer |
| Credit Analyst | Finance / Credit | Blocked orders, age, customer exposure against credit limit |
| Billing Lead | Finance / Billing | Delivered-not-billed list and aging, cancelled invoices |
| Sales Director | Sales | Revenue by month, region, customer and material group |
| SAP SD Analyst (BSA) | IT | Owns requirements, data model, testing and handover |

## 5. Scope

In scope: standard sales orders (OR), outbound deliveries (LF), invoices (F2) and invoice cancellations (S1) for sales org 1000, calendar year 2025.

Out of scope for this release: returns and credit memos, intercompany billing, open AR and payments (FI-AR), pricing condition analysis, rebates.

## 6. Source data

| SAP table | Content | Key fields used |
|---|---|---|
| KNA1 | Customer master | KUNNR, NAME1, REGIO |
| UKMBP_CMS_SGM (simplified as CUSTOMER_CREDIT) | Credit limit and risk class | CREDIT_LIMIT, RISK_CLASS |
| MARA / MAKT | Material master | MATNR, MAKTX, MATKL |
| VBAK | Sales order header | ERDAT, KUNNR, NETWR, CMGST, LIFSK, FAKSK |
| VBAP | Sales order item | MATNR, KWMENG, NETPR, NETWR, ABGRU |
| VBEP | Schedule line | EDATU, WMENG, BMENG |
| LIKP / LIPS | Delivery header and item | WADAT_IST, LFDAT, LFIMG, VGBEL, VGPOS |
| VBRK / VBRP | Billing header and item | FKART, FKDAT, FKSTO, SFAKN, AUBEL, AUPOS |

In production this would come from a nightly extract (CDS views or SLT replication into SQL Server). For this project the extract is simulated with CSV files.

## 7. User stories

US-01. As a Credit Analyst, I want a list of orders on credit block with order value and days blocked, so that I can work the oldest and largest ones first.
Acceptance criteria:
- Shows every order with VBAK-CMGST = B.
- Days blocked = report date minus order creation date.
- Sorted by days blocked, oldest first, and filterable by customer and risk class.
- Total blocked value matches the SQL query KPI-04.

US-02. As a Credit Analyst, I want to see each customer's open exposure against the credit limit, so that I can spot customers over their limit.
Acceptance criteria:
- Open exposure = value of open, blocked and in-shipping items plus delivered-not-billed value.
- Credit used % = open exposure / credit limit.
- Customers over 100% are highlighted in red, 75 to 100% in amber.

US-03. As a Customer Service Manager, I want to see backordered quantity and value by material and customer, so that I can tell customers early and work with supply planning.
Acceptance criteria:
- Backorder qty = requested qty (VBEP-WMENG) minus confirmed qty (VBEP-BMENG), rejected items excluded.
- Drill from material to the order items behind it.

US-04. As a Customer Service Manager, I want on-time delivery % by month, customer and region, so that I can follow up on late shipments.
Acceptance criteria:
- A delivery is on time when actual goods issue date (LIKP-WADAT_IST) is on or before the requested date (LIKP-LFDAT).
- Only deliveries with goods issue posted are counted.

US-05. As a Billing Lead, I want a list of items that are goods-issued but not billed, with aging, so that revenue is not left behind at month end.
Acceptance criteria:
- Includes items with goods issue posted and no valid F2 invoice.
- Aging buckets: 0-3 days, 4-7 days, 8+ days from goods issue to report date.
- Shows the billing block (VBAK-FAKSK) where one is set, since that is the usual cause.

US-06. As a Sales Director, I want net billed revenue by month, region, customer and material group, so that I can track performance against plan.
Acceptance criteria:
- Counts only F2 invoices that are not cancelled (VBRK-FKSTO blank). S1 cancellation documents are excluded.
- Monthly totals match KPI-01.

US-07. As a Sales Director, I want the average order-to-invoice cycle time by month, so that I can see whether the process is getting faster.
Acceptance criteria:
- Calculated per order: last valid invoice date minus order creation date, in calendar days.
- Orders with no valid invoice are excluded.

US-08. As any user, I want to see one order's full flow (order, delivery, invoice, status), so that I do not need to open VA03.
Acceptance criteria:
- Drill-through page from any visual to the order detail.
- Status follows the rules in section 8.

## 8. KPI and status definitions

| ID | KPI | Definition |
|---|---|---|
| KPI-01 | Net billed revenue | Sum of VBRP-NETWR for F2 invoices with FKSTO blank |
| KPI-02 | Order-to-invoice days | Avg of (last valid FKDAT minus VBAK-ERDAT) per invoiced order |
| KPI-03 | On-time delivery % | Deliveries with WADAT_IST <= LFDAT / deliveries with WADAT_IST |
| KPI-04 | Credit-blocked orders | Count and VBAK-NETWR of orders with CMGST = B, with age |
| KPI-05 | Credit release time | Avg days from ERDAT to release date for orders with CMGST = D |
| KPI-06 | Backorder value | Sum of (WMENG minus BMENG) x NETPR, rejected items excluded |
| KPI-07 | Delivered not billed | Sum of LFIMG x NETPR for goods-issued items with no valid invoice |
| KPI-08 | Fill rate % | Sum of BMENG / sum of KWMENG, rejected items excluded |
| KPI-09 | Item status mix | Count and value of items by status (below) |
| KPI-10 | Credit used % | Open exposure / credit limit, by customer |

Item status is assigned in this order, first match wins:

1. Rejected: VBAP-ABGRU is set
2. Credit Block: VBAK-CMGST = B
3. Delivery Block: VBAK-LIFSK is set
4. Billed: a valid F2 invoice exists
5. Delivered Not Billed: goods issue posted, no valid invoice
6. In Shipping: delivery created, goods issue not posted
7. Backordered: confirmed qty is zero
8. Open Order: anything else

## 9. Non-functional requirements

- Refresh daily at 6:00 AM Central, before Customer Service starts.
- Report pages load in under 5 seconds.
- Row-level security by sales region for the Sales team (phase 2).
- Credit pages visible to Finance only.

## 10. Assumptions and open questions

- One schedule line per item. Real data can have several; the view would need to sum them.
- Credit status values follow the S/4HANA codes (A passed, B blocked, D released). The release date would come from the change log (CDHDR/CDPOS) in a real system.
- Open exposure leaves out open AR, so it understates real exposure. Finance should confirm whether to add FI-AR in phase 2.
- Open question for the Credit team: should orders blocked longer than 90 days be rejected automatically? Ten of the fourteen blocked orders are past 90 days.
