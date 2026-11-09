# Using this project in your job search

## Resume (Projects section)

Order-to-Cash Performance Dashboard | SAP SD data model, SQL Server, Power BI | [GitHub link]
- Wrote business requirements and 8 user stories for an OTC dashboard covering credit blocks, backorders, on-time delivery, delivered-not-billed and revenue, using SAP SD tables (VBAK/VBAP/VBEP, LIKP/LIPS, VBRK/VBRP).
- Built SQL Server views that follow each order item through delivery and billing, with status rules for partial confirmations, credit and billing blocks, rejections and S1 cancellations.
- Defined 10 KPIs and tested them against an independent Python calculation; found $56.6K shipped but unbilled because of billing blocks that were never released, and 10 orders on credit block for more than 90 days.

## LinkedIn post

I built a small order-to-cash dashboard project to practice the reporting side of SAP SD.

The setup is a made-up lab supply distributor with a year of sales orders, deliveries and invoices, all shaped like the real SD tables. I wrote the requirements first, then the SQL views, then the Power BI report.

Two things I ran into that also come up on real projects:

1. Revenue has to exclude cancelled invoices and the S1 cancellation documents, or a re-billed order gets counted twice.
2. A partially confirmed item can show as billed and still carry a backorder, so the status logic has to handle both.

The most useful finding was the delivered-not-billed list. Every item older than a week had a billing block nobody released.

All the data is synthetic. Repo link in the comments if you want to look at the SQL or the test cases.

#SAP #SAPSD #OrderToCash #PowerBI #BusinessAnalysis

## Interview walkthrough (about 2 minutes)

Use this when you get "tell me about a project" or "how do you approach reporting requirements".

Situation. I wanted to show how I handle an SD reporting request from start to finish, so I set up a fictional distributor where Customer Service, Credit and Billing each had their own Excel report and the numbers never matched.

What I did. I started with the requirements: who uses the report, what decisions they make from it, and how each KPI is defined in terms of SAP fields. For example, on-time means actual goods issue on or before the requested date, and revenue only counts F2 invoices that are not cancelled. Then I built a SQL view that follows each order item from VBAP through LIPS to VBRP, the same thing you see in document flow, and gave every item one status. I wrote test cases with expected numbers, calculated them separately in Python, and made sure the SQL matched before I started on Power BI.

Result. The report pointed straight at the exceptions. Ten orders had been on credit block for over 90 days with no owner, one customer was at 132% of its credit limit, and $56K had shipped but was not billed because of billing blocks. Those are the conversations you want to have with the business.

What I'd do next. Add open AR from FI to the credit exposure, and set up row-level security by region.

Questions they may ask, and short answers:
- Why build the status logic in SQL and not DAX? It is easier to test, and other tools can reuse it, such as an SSRS report for the billing team.
- How would this work against a real system? I would source from CDS views or a nightly extract instead of CSVs, and pull the credit release date from the change documents (CDHDR/CDPOS).
- What was the hardest part? Defining the rules. Things like whether a partially shipped item counts as backordered took more thought than the SQL.
