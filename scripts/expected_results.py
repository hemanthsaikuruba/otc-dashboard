"""
Computes the expected KPI values straight from the CSVs with pandas.
This is an independent check of the SQL: if the SQL output and these
numbers match, the logic is right. Results feed docs/test_cases.md.

Usage:  python expected_results.py [data_dir]
"""
import sys
from pathlib import Path
import pandas as pd

d = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "data")
ASOF = pd.Timestamp("2025-12-31")
rd = lambda n, **k: pd.read_csv(d / f"{n}.csv", dtype=str, keep_default_na=False, **k)

kna1, cred, mara = rd("KNA1"), rd("CUSTOMER_CREDIT"), rd("MARA")
vbak, vbap, vbep = rd("VBAK"), rd("VBAP"), rd("VBEP")
likp, lips, vbrk, vbrp = rd("LIKP"), rd("LIPS"), rd("VBRK"), rd("VBRP")

for df, cols in [(vbak, ["ERDAT", "CREDIT_RELEASE_DATE"]), (vbep, ["EDATU"]), (likp, ["ERDAT", "LFDAT", "WADAT_IST"]),
                 (vbrk, ["FKDAT"])]:
    for c in cols:
        df[c] = pd.to_datetime(df[c].replace("", None))
for df, cols in [(vbak, ["NETWR"]), (vbap, ["KWMENG", "NETPR", "NETWR"]), (vbep, ["WMENG", "BMENG"]),
                 (lips, ["LFIMG"]), (vbrk, ["NETWR"]), (vbrp, ["FKIMG", "NETWR"]), (cred, ["CREDIT_LIMIT"])]:
    for c in cols:
        df[c] = df[c].astype(float)

print("TC-01 row counts")
for n, df in [("KNA1", kna1), ("CUSTOMER_CREDIT", cred), ("MARA", mara), ("VBAK", vbak), ("VBAP", vbap),
              ("VBEP", vbep), ("LIKP", likp), ("LIPS", lips), ("VBRK", vbrk), ("VBRP", vbrp)]:
    print(f"  {n}: {len(df)}")

valid = vbrk[(vbrk.FKART == "F2") & (vbrk.FKSTO != "X")]
bill = vbrp.merge(valid[["VBELN", "FKDAT"]], on="VBELN")

print("\nKPI-01 net billed revenue by month")
m = bill.assign(mon=bill.FKDAT.dt.strftime("%Y-%m")).groupby("mon").agg(invoices=("VBELN", "nunique"), rev=("NETWR", "sum"))
for k, r in m.iterrows():
    print(f"  {k}  {int(r.invoices):4d}  {r.rev:,.2f}")
print(f"  TOTAL {m.invoices.sum()} invoices  {m.rev.sum():,.2f}")

print("\nKPI-02 order-to-invoice days")
oi = bill.groupby("AUBEL").FKDAT.max().rename("last").reset_index().merge(vbak[["VBELN", "ERDAT"]], left_on="AUBEL", right_on="VBELN")
oi["days"] = (oi["last"] - oi.ERDAT).dt.days
mm = oi.assign(mon=oi.ERDAT.dt.strftime("%Y-%m")).groupby("mon").days.agg(["count", "mean"])
for k, r in mm.iterrows():
    print(f"  {k}  {int(r['count']):4d}  {r['mean']:.1f}")
print(f"  OVERALL {len(oi)} orders, avg {oi.days.mean():.1f} days")

print("\nKPI-03 on-time delivery")
sh = likp[likp.WADAT_IST.notna()]
ot = (sh.WADAT_IST <= sh.LFDAT).sum()
print(f"  shipped {len(sh)}, on time {ot}, pct {100*ot/len(sh):.1f}")

print("\nKPI-04 credit blocked orders")
cb = vbak[vbak.CMGST == "B"].merge(kna1[["KUNNR", "NAME1"]], on="KUNNR")
cb["age"] = (ASOF - cb.ERDAT).dt.days
print(f"  count {len(cb)}, value {cb.NETWR.sum():,.2f}, oldest {cb.age.max()} days, avg age {cb.age.mean():.1f}")
for _, r in cb.sort_values("age", ascending=False).iterrows():
    print(f"    {r.VBELN} {r.ERDAT.date()} {r.NAME1:35s} {r.NETWR:>10,.2f} {r.age}")

print("\nKPI-05 credit release time")
rel = vbak[vbak.CMGST == "D"]
print(f"  released {len(rel)}, avg days {((rel.CREDIT_RELEASE_DATE - rel.ERDAT).dt.days).mean():.1f}")

items = vbap.merge(vbep[vbep.ETENR == "0001"], on=["VBELN", "POSNR"]).merge(vbak[["VBELN", "ERDAT", "KUNNR", "CMGST", "LIFSK"]], on="VBELN")
items["rej"] = items.ABGRU != ""
items["bo_qty"] = (items.WMENG - items.BMENG).where(~items.rej, 0)
items["bo_val"] = items.bo_qty * items.NETPR

print("\nKPI-06 backorders by material")
bo = items[items.bo_qty > 0].groupby("MATNR").agg(n=("POSNR", "count"), q=("bo_qty", "sum"), v=("bo_val", "sum")).sort_values("v", ascending=False)
for k, r in bo.iterrows():
    print(f"  {k}  {int(r.n):3d}  {r.q:8.0f}  {r.v:,.2f}")
print(f"  TOTAL items {bo.n.sum()}, qty {bo.q.sum():.0f}, value {bo.v.sum():,.2f}")

dl = lips.merge(likp[["VBELN", "WADAT_IST"]], on="VBELN")
billed_keys = set(zip(bill.AUBEL, bill.AUPOS))
dl["billed"] = [(a, b) in billed_keys for a, b in zip(dl.VGBEL, dl.VGPOS)]
dnb = dl[dl.WADAT_IST.notna() & ~dl.billed].merge(vbap[["VBELN", "POSNR", "NETPR"]], left_on=["VGBEL", "VGPOS"], right_on=["VBELN", "POSNR"], suffixes=("", "_so"))
dnb["val"] = dnb.LFIMG * dnb.NETPR
dnb["age"] = (ASOF - dnb.WADAT_IST).dt.days
dnb["bucket"] = pd.cut(dnb.age, [-1, 3, 7, 10**6], labels=["0-3 days", "4-7 days", "8+ days"])
print("\nKPI-07 delivered not billed")
g = dnb.groupby("bucket", observed=False).agg(orders=("VGBEL", "nunique"), val=("val", "sum"))
for k, r in g.iterrows():
    print(f"  {k}  {int(r.orders)}  {r.val:,.2f}")
print(f"  TOTAL orders {dnb.VGBEL.nunique()}, value {dnb.val.sum():,.2f}")

print("\nKPI-08 fill rate")
nr = items[~items.rej]
print(f"  confirmed {nr.BMENG.sum():.0f} / ordered {nr.KWMENG.sum():.0f} = {100*nr.BMENG.sum()/nr.KWMENG.sum():.1f}%")

print("\nKPI-09 item status")
dkeys = set(zip(dl.VGBEL, dl.VGPOS))
gikeys = set(zip(dl[dl.WADAT_IST.notna()].VGBEL, dl[dl.WADAT_IST.notna()].VGPOS))
def status(r):
    k = (r.VBELN, r.POSNR)
    if r.rej: return "Rejected"
    if r.CMGST == "B": return "Credit Block"
    if r.LIFSK != "": return "Delivery Block"
    if k in billed_keys: return "Billed"
    if k in gikeys: return "Delivered Not Billed"
    if k in dkeys: return "In Shipping"
    if r.BMENG == 0: return "Backordered"
    return "Open Order"
items["status"] = items.apply(status, axis=1)
st = items.groupby("status").agg(n=("POSNR", "count"), v=("NETWR", "sum")).sort_values("n", ascending=False)
for k, r in st.iterrows():
    print(f"  {k:22s} {int(r.n):5d}  {r.v:,.2f}")

print("\nKPI-10 top customers by revenue")
rev = bill.merge(valid[["VBELN", "KUNRG"]], on="VBELN").groupby("KUNRG").NETWR.sum().rename("rev")
items_gi = items.merge(dl.groupby(["VGBEL", "VGPOS"]).LFIMG.sum().rename("dq").reset_index(), left_on=["VBELN", "POSNR"], right_on=["VGBEL", "VGPOS"], how="left")
open_st = ["Open Order", "Backordered", "In Shipping", "Credit Block", "Delivery Block"]
items_gi["exp"] = items_gi.NETWR.where(items_gi.status.isin(open_st), 0) + (items_gi.dq.fillna(0) * items_gi.NETPR).where(items_gi.status == "Delivered Not Billed", 0)
exp = items_gi.groupby("KUNNR").exp.sum()
t = kna1.merge(cred, on="KUNNR").set_index("KUNNR").join(rev).join(exp).sort_values("rev", ascending=False)
for k, r in t.iterrows():
    print(f"  {r.NAME1:35s} {r.REGION:9s} {r.RISK_CLASS:6s} {r.rev:>12,.2f} {r.exp:>11,.2f} {100*r.exp/r.CREDIT_LIMIT:5.1f}%")
