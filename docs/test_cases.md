# Test cases

Expected values come from `scripts/expected_results.py`, which calculates every KPI from the CSV files with pandas and does not use the SQL. The SQL views and queries were then run against the same data and returned the same numbers. Use this sheet to test the SQL load first, then the Power BI report.

Report date for all aging: 2025-12-31.

## Data load

| ID | Test | Expected result | Status |
|---|---|---|---|
| TC-01 | Row counts after running 02_load_data.sql | KNA1 12, CUSTOMER_CREDIT 12, MARA 12, VBAK 650, VBAP 1,645, VBEP 1,645, LIKP 613, LIPS 1,495, VBRK 617, VBRP 1,494 | Pass |
| TC-02 | Data quality checks (DQ-01 in 04_kpi_queries.sql) | All six checks return 0 failures | Pass |
| TC-03 | Blank flags load as NULL | `SELECT COUNT(*) FROM otc.VBAP WHERE ABGRU = ''` returns 0 | Pass |

## KPI results (SQL and Power BI)

| ID | KPI | Expected result | SQL | Power BI |
|---|---|---|---|---|
| TC-10 | KPI-01 net billed revenue, full year | $2,924,097.28 from 599 invoices | Pass | Pass |
| TC-11 | KPI-01 October 2025 | $378,670.19 from 68 invoices (highest month) | Pass | Pass |
| TC-12 | KPI-01 January 2025 | $125,883.22 from 27 invoices | Pass | Pass |
| TC-13 | KPI-02 order-to-invoice days, overall | 10.2 days across 599 orders | Pass | Pass |
| TC-14 | KPI-02 July 2025 orders | 11.3 days across 43 orders (slowest month) | Pass | Pass |
| TC-15 | KPI-03 on-time delivery | 415 of 608 shipped deliveries = 68.3% | Pass | |
| TC-16 | KPI-04 credit-blocked orders | 14 orders, $90,715.63, oldest 362 days (order 0001000006) | Pass | Pass |
| TC-17 | KPI-05 credit release time | 58 released orders, 4.8 days average | N/A | |
| TC-18 | KPI-06 backorders, total | 137 items, 2,455 units, $188,939.06 | Pass | Pass |
| TC-19 | KPI-06 top backorder material | LAB-2001 Rapid Test Reagent Kit: 45 items, 496 units, $67,464.15 | Pass | Pass |
| TC-20 | KPI-07 delivered not billed, total | 9 orders, $56,572.64 | Pass | Pass |
| TC-21 | KPI-07 aging buckets | 0-3 days: 3 orders $21,964.82; 4-7 days: 2 orders $9,029.12; 8+ days: 4 orders $25,578.70 | Pass | Pass |
| TC-22 | KPI-08 fill rate | 69,737 / 72,192 = 96.6% | Pass | Pass |
| TC-23 | KPI-09 status mix (items) | Billed 1,454; Credit Block 40; Backordered 39; Rejected 34; Delivery Block 30; Delivered Not Billed 27; In Shipping 14; Open Order 7 (total 1,645) | Pass | Pass |
| TC-24 | KPI-10 top customer by revenue | Gulf Coast Diagnostics, $371,932.50 | Pass | Pass |
| TC-25 | KPI-10 customer over credit limit | Riverbend Community Clinic only: $52,948.00 exposure on a $40,000 limit = 132.4% | Pass | Pass |
| TC-26 | Reconciliation, billing documents | 617 documents in VBRK = 599 in vw_FactBilling + 9 cancelled F2 + 9 S1 cancellations | Pass | |
| TC-27 | Reconciliation, billing items | 1,494 items in VBRP = 1,454 in vw_FactBilling + 20 on cancelled F2 + 20 on S1 | Pass | |
| TC-28 | Reconciliation, billed revenue | $2,924,097.28 in vw_FactBilling; cancelled F2 and S1 each carry $34,141.13 and are excluded | Pass | |

## Scenario tests (follow one document through the flow)

### TC-30. Credit block stays out of delivery and billing

Steps: filter the order detail page to sales order 0001000006.

Expected: credit status B, status Credit Block on every item, no delivery, no invoice, days blocked 362. Customer is Riverbend Community Clinic (risk class HIGH).

### TC-31. Cancelled invoice is excluded from revenue

Steps: look up sales order 0001000151 in VBRK/VBRP and in the report.

Expected: three billing documents. 0090000143 (F2, 2025-04-01, cancelled, FKSTO = X), 0090000144 (S1 cancelling 0090000143) and 0090000145 (the re-bill F2). Revenue for the order is counted once, from 0090000145. The report shows 0090000145 as the invoice.

### TC-32. Partial confirmation creates a backorder but the confirmed part still flows

Steps: open sales order 0001000013, item 000020.

Expected: requested 8, confirmed 3, backorder qty 5. The 3 confirmed units were delivered and billed, so the item status is Billed and the backorder qty still shows 5.

### TC-33. Billing block holds an item in Delivered Not Billed

Steps: filter the delivered-not-billed list to billing block 02.

Expected: five orders (0001000566, 0001000576, 0001000577, 0001000621, 0001000641), all goods-issued and none invoiced. All four orders in the 8+ day bucket have this block, which is the finding to raise with the Billing team. (A sixth order, 0001000645, has the block but has not shipped yet, so it does not appear.)

### TC-34. Rejected items are left out of value and fill rate

Steps: pick any item with ABGRU = 02.

Expected: status Rejected, not counted in backorder qty, not in fill rate, not in VBAK-NETWR for the order.

## Power BI checks

| ID | Test | Expected result | Status |
|---|---|---|---|
| TC-40 | Slicing by region does not change grand totals when cleared | Revenue returns to $2,924,097.28 | Pass | |
| TC-41 | Month slicer on Executive page filters revenue by invoice date and cycle time by order date | December 2025 revenue $330,129.93 | Pass | |
| TC-42 | Drill-through from any customer bar opens Order Detail filtered to that customer | Only that customer's orders show | Pass | |
| TC-43 | Credit used % formatting | Riverbend red (over 100%), Piedmont Pharma Supply amber (76.0%) | Pass | |
