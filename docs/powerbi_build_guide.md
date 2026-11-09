# Power BI build guide

This is the step-by-step for building the report on top of the SQL views. Plan on 6 to 10 hours if you are comfortable with Power BI.

## 1. Set up the database

1. Install SQL Server 2022 Developer edition and SSMS. Both are free.
2. Copy the `data` folder to `C:\otc-dashboard\data\` (or change `@path` in `02_load_data.sql`).
3. Run the scripts in order: `01_create_tables.sql`, `02_load_data.sql`, `03_views.sql`.
4. Run `04_kpi_queries.sql` and compare the output with `docs/test_cases.md`. Do not start on Power BI until TC-01 to TC-25 pass in SQL.

## 2. Load the model

Get Data, SQL Server, server `localhost`, database `OTC_Portfolio`, Import mode. Select these four views:

| Power BI table | Source view | Grain |
|---|---|---|
| FactItemFlow | otc.vw_OTC_ItemFlow | One row per sales order item |
| FactBilling | otc.vw_FactBilling | One row per valid invoice item |
| DimCustomer | otc.vw_DimCustomer | One row per customer |
| DimMaterial | otc.vw_DimMaterial | One row per material |

In Power Query, set SALES_ORDER, ITEM, DELIVERY and INVOICE to Text so the leading zeros stay.

Add a date table (Modeling, New table):

```DAX
DimDate =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2025, 1, 1 ), DATE ( 2026, 1, 31 ) ),
    "Year", YEAR ( [Date] ),
    "Month", FORMAT ( [Date], "MMM yyyy" ),
    "MonthSort", YEAR ( [Date] ) * 100 + MONTH ( [Date] )
)
```

Mark it as a date table and sort Month by MonthSort.

## 3. Relationships

All one-to-many, single direction:

- DimCustomer[CUSTOMER] to FactItemFlow[CUSTOMER] and FactBilling[CUSTOMER]
- DimMaterial[MATERIAL] to FactItemFlow[MATERIAL] and FactBilling[MATERIAL]
- DimDate[Date] to FactItemFlow[ORDER_DATE] (active)
- DimDate[Date] to FactBilling[INVOICE_DATE] (active)

Because the two facts hang off the same date table on different dates, the month slicer filters revenue by invoice date and order metrics by order date. Put a note on the Executive page saying so. Reviewers like seeing that you thought about it.

## 4. Measures

Create a blank table called _Measures and add these:

```DAX
Net Revenue = SUM ( FactBilling[NET_REVENUE] )

Invoices = DISTINCTCOUNT ( FactBilling[INVOICE] )

Avg Order to Invoice Days =
VAR Orders =
    ADDCOLUMNS (
        SUMMARIZE (
            FILTER ( FactItemFlow, NOT ISBLANK ( FactItemFlow[INVOICE_DATE] ) ),
            FactItemFlow[SALES_ORDER], FactItemFlow[ORDER_DATE]
        ),
        "@LastInvoice", CALCULATE ( MAX ( FactItemFlow[INVOICE_DATE] ) )
    )
RETURN
    AVERAGEX ( Orders, DATEDIFF ( FactItemFlow[ORDER_DATE], [@LastInvoice], DAY ) )

On Time Delivery % =
DIVIDE (
    CALCULATE ( DISTINCTCOUNT ( FactItemFlow[DELIVERY] ), FactItemFlow[IS_ON_TIME] = 1 ),
    CALCULATE ( DISTINCTCOUNT ( FactItemFlow[DELIVERY] ), NOT ISBLANK ( FactItemFlow[GI_DATE] ) )
)

Credit Blocked Orders =
CALCULATE ( DISTINCTCOUNT ( FactItemFlow[SALES_ORDER] ), FactItemFlow[CREDIT_STATUS] = "B" )

Credit Blocked Value =
CALCULATE ( SUM ( FactItemFlow[ORDER_VALUE] ), FactItemFlow[ITEM_STATUS] = "Credit Block" )

Backorder Qty = SUM ( FactItemFlow[BACKORDER_QTY] )

Backorder Value = SUM ( FactItemFlow[BACKORDER_VALUE] )

Delivered Not Billed Value =
SUMX (
    FILTER ( FactItemFlow, NOT ISBLANK ( FactItemFlow[GI_DATE] ) && ISBLANK ( FactItemFlow[INVOICE] ) ),
    FactItemFlow[GI_QTY] * FactItemFlow[NET_PRICE]
)

Fill Rate % =
DIVIDE (
    CALCULATE ( SUM ( FactItemFlow[CONFIRMED_QTY] ), FactItemFlow[IS_REJECTED] = 0 ),
    CALCULATE ( SUM ( FactItemFlow[ORDER_QTY] ), FactItemFlow[IS_REJECTED] = 0 )
)

Open Exposure =
CALCULATE (
    SUM ( FactItemFlow[ORDER_VALUE] ),
    FactItemFlow[ITEM_STATUS] IN { "Open Order", "Backordered", "In Shipping", "Credit Block", "Delivery Block" }
) + [Delivered Not Billed Value]

Credit Used % = DIVIDE ( [Open Exposure], MAX ( DimCustomer[CREDIT_LIMIT] ) )
```

Credit Used % only makes sense at customer level, so use it in a table with one row per customer.

For aging, add a calculated column on FactItemFlow:

```DAX
DNB Aging Bucket =
IF (
    NOT ISBLANK ( FactItemFlow[GI_DATE] ) && ISBLANK ( FactItemFlow[INVOICE] ),
    VAR Age = DATEDIFF ( FactItemFlow[GI_DATE], DATE ( 2025, 12, 31 ), DAY )
    RETURN SWITCH ( TRUE (), Age <= 3, "0-3 days", Age <= 7, "4-7 days", "8+ days" )
)
```

The report date is fixed at 2025-12-31 because the data stops there. In a live report you would use TODAY().

## 5. Report pages

Page 1, Executive summary
- KPI cards: Net Revenue, Avg Order to Invoice Days, On Time Delivery %, Fill Rate %
- Line chart: Net Revenue by Month
- Column chart: Avg Order to Invoice Days by Month
- Bar chart: Net Revenue by Region
- Slicers: Month, Region, Material Group

Page 2, Order pipeline and credit
- Funnel or bar: item count by ITEM_STATUS
- Table: credit-blocked orders (order, customer, risk class, value, days blocked), sorted by days blocked
- Table: customers with Net Revenue, Open Exposure, Credit Limit, Credit Used % with conditional formatting (red over 100%, amber 75 to 100%)
- Card: Credit Blocked Value

Page 3, Delivery and backorders
- Line chart: On Time Delivery % by Month
- Bar chart: Backorder Value by material
- Matrix: customer by material with Backorder Qty
- Card: Fill Rate %

Page 4, Billing
- Column chart: Delivered Not Billed Value by DNB Aging Bucket
- Table: delivered-not-billed items with order, customer, GI date, billing block, value
- Card: count of cancelled invoices (add a small query on VBRK FKSTO = X if you want this)

Page 5, Order detail (drill-through)
- Drill-through field: SALES_ORDER
- Table with every column from FactItemFlow for the order, so a user can follow order, delivery and invoice without opening VA03

## 6. Before you publish

Run the Power BI column of `docs/test_cases.md`. Take screenshots of each page for the README. If you publish to the web, double-check that it only contains this synthetic data.

## Optional extensions

- An SSRS paginated report of the delivered-not-billed list for the Billing team's daily email.
- Row-level security by region (Modeling, Manage roles, filter DimCustomer[REGION]).
- A second year of data so you can show year-over-year. Change START, END_ORDERS and CUTOFF in `generate_data.py`.
