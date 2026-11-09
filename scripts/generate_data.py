"""
Generates synthetic SAP SD order-to-cash data for a fictional company,
Northfield Lab Supply Co. Table and field names follow standard SAP SD
tables (KNA1, MARA, VBAK, VBAP, VBEP, LIKP, LIPS, VBRK, VBRP) so the
SQL and Power BI work looks like it does against a real system.

All data is made up. Seeded, so every run produces the same files.

Usage:  python generate_data.py [output_dir]
"""
import csv
import random
import sys
from datetime import date, timedelta
from pathlib import Path

SEED = 42
START = date(2025, 1, 2)
END_ORDERS = date(2025, 12, 30)
CUTOFF = date(2025, 12, 31)   # "report as of" date
N_ORDERS = 650

rng = random.Random(SEED)
out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "data")
out.mkdir(parents=True, exist_ok=True)


def workday(d):
    while d.weekday() >= 5:
        d += timedelta(days=1)
    return d


def add_workdays(d, n):
    step = 1 if n >= 0 else -1
    for _ in range(abs(n)):
        d += timedelta(days=step)
        while d.weekday() >= 5:
            d += timedelta(days=step)
    return d


def fmt(d):
    return d.isoformat() if d else ""


# ---------------------------------------------------------------- master data
customers = [
    # KUNNR, NAME1, ORT01, REGIO, KTOKD, risk class, credit limit, discount, weight
    ("0000100001", "Lakeview Regional Hospital", "Chicago", "IL", "Z001", "LOW", 400000, 0.08, 9),
    ("0000100002", "Prairie State University Labs", "Champaign", "IL", "Z001", "LOW", 250000, 0.10, 7),
    ("0000100003", "Gulf Coast Diagnostics", "Houston", "TX", "Z001", "MEDIUM", 150000, 0.05, 8),
    ("0000100004", "Summit Health Network", "Denver", "CO", "Z001", "LOW", 350000, 0.07, 8),
    ("0000100005", "Bayside Clinical Research", "San Diego", "CA", "Z001", "MEDIUM", 120000, 0.04, 6),
    ("0000100006", "Great Lakes Medical Distributors", "Detroit", "MI", "Z002", "HIGH", 90000, 0.12, 7),
    ("0000100007", "Riverbend Community Clinic", "St. Louis", "MO", "Z001", "HIGH", 40000, 0.00, 5),
    ("0000100008", "Atlantic BioServices", "Boston", "MA", "Z001", "LOW", 300000, 0.06, 6),
    ("0000100009", "Desert Valley Labs", "Phoenix", "AZ", "Z001", "MEDIUM", 80000, 0.03, 5),
    ("0000100010", "Piedmont Pharma Supply", "Charlotte", "NC", "Z002", "HIGH", 70000, 0.11, 6),
    ("0000100011", "Cascade Research Institute", "Seattle", "WA", "Z001", "LOW", 200000, 0.05, 5),
    ("0000100012", "Heartland Veterinary Group", "Omaha", "NE", "Z001", "MEDIUM", 60000, 0.02, 4),
]
REGION = {"IL": "Midwest", "MI": "Midwest", "MO": "Midwest", "NE": "Midwest",
          "TX": "South", "NC": "South", "AZ": "West", "CA": "West", "CO": "West",
          "WA": "West", "MA": "Northeast"}

materials = [
    # MATNR, MAKTX, MATKL, MEINS, list price, typical qty range
    ("LAB-1001", "Nitrile Gloves Box (100)", "CONSUM", "BX", 14.50, (20, 200)),
    ("LAB-1002", "Pipette Tips Rack (96)", "CONSUM", "PAC", 9.75, (20, 300)),
    ("LAB-1003", "Specimen Containers (50)", "CONSUM", "PAC", 22.00, (10, 120)),
    ("LAB-1004", "Sterile Swab Kit (25)", "CONSUM", "KIT", 18.25, (10, 150)),
    ("LAB-2001", "Rapid Test Reagent Kit", "REAGENT", "KIT", 145.00, (2, 40)),
    ("LAB-2002", "Buffer Solution 1L", "REAGENT", "EA", 38.00, (5, 60)),
    ("LAB-2003", "Staining Reagent Set", "REAGENT", "KIT", 210.00, (1, 20)),
    ("LAB-3001", "Benchtop Centrifuge", "EQUIP", "EA", 3450.00, (1, 2)),
    ("LAB-3002", "Digital Micropipette", "EQUIP", "EA", 289.00, (1, 10)),
    ("LAB-3003", "Lab Refrigerator 20 cu ft", "EQUIP", "EA", 5200.00, (1, 1)),
    ("LAB-4001", "Biohazard Bags (200)", "SAFETY", "BX", 31.00, (5, 80)),
    ("LAB-4002", "Safety Goggles (12)", "SAFETY", "PAC", 42.00, (2, 30)),
]
mat_weights = [10, 10, 7, 7, 6, 6, 3, 1, 3, 1, 5, 4]

# Material availability problems drive backorders (two items are chronically short)
short_supply = {"LAB-2001": 0.30, "LAB-3002": 0.25}

PLANT = "1000"
VKORG, VTWEG, SPART = "1000", "10", "00"
VSTEL = "1000"

with open(out / "KNA1.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["KUNNR", "NAME1", "ORT01", "REGIO", "LAND1", "KTOKD", "REGION"])
    for c in customers:
        w.writerow([c[0], c[1], c[2], c[3], "US", c[4], REGION[c[3]]])

# In S/4HANA credit data sits in FSCM (UKMBP_CMS_SGM). Simplified here.
with open(out / "CUSTOMER_CREDIT.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["KUNNR", "CREDIT_SEGMENT", "CREDIT_LIMIT", "RISK_CLASS", "WAERS"])
    for c in customers:
        w.writerow([c[0], "1000", c[6], c[5], "USD"])

with open(out / "MARA.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["MATNR", "MAKTX", "MATKL", "MEINS", "LIST_PRICE"])
    for m in materials:
        w.writerow([m[0], m[1], m[2], m[3], f"{m[4]:.2f}"])

# ---------------------------------------------------------------- transactions
vbak, vbap, vbep, likp, lips, vbrk, vbrp = [], [], [], [], [], [], []
order_no, deliv_no, bill_no = 1000000, 80000000, 90000000
cust_w = [c[8] for c in customers]
days_span = (END_ORDERS - START).days

# Sort order dates first so document numbers run in date order, like a real system
order_dates = sorted(workday(START + timedelta(days=rng.randint(0, days_span))) for _ in range(N_ORDERS))

for erdat in order_dates:
    order_no += 1
    vbeln = f"{order_no:010d}"
    cust = rng.choices(customers, weights=cust_w)[0]
    kunnr, risk, disc = cust[0], cust[5], cust[7]

    # Order header flags
    credit_roll = rng.random()
    if risk == "HIGH" and credit_roll < 0.25 or risk == "MEDIUM" and credit_roll < 0.03:
        cmgst = "B"                                  # blocked by credit check
    elif risk == "HIGH" and credit_roll < 0.40 or risk == "MEDIUM" and credit_roll < 0.08:
        cmgst = "D"                                  # blocked, then released by credit team
    else:
        cmgst = "A"                                  # check passed
    credit_release = add_workdays(erdat, rng.randint(1, 4)) if cmgst == "D" else None
    # Blocked orders placed long ago would normally have been released or rejected.
    # Keep blocked ones mostly in the last two months so the aging looks realistic.
    if cmgst == "B" and (CUTOFF - erdat).days > 60 and rng.random() < 0.75:
        cmgst = "D"
        credit_release = add_workdays(erdat, rng.randint(2, 8))
    lifsk = "01" if rng.random() < 0.02 else ""      # delivery block
    faksk = "02" if rng.random() < 0.04 else ""      # billing block
    if faksk and (CUTOFF - erdat).days > 45:
        faksk = ""                                   # old billing blocks get cleared

    n_items = rng.choices([1, 2, 3, 4, 5], weights=[25, 30, 25, 12, 8])[0]
    mats = rng.sample(range(len(materials)), k=n_items)
    lead = rng.randint(3, 8)
    edatu = add_workdays(erdat, lead)                 # requested delivery date

    items = []
    for i, mi in enumerate(mats, start=1):
        posnr = f"{i * 10:06d}"
        m = materials[mi]
        qty = rng.randint(*m[5])
        price = round(m[4] * (1 - disc), 2)
        netwr = round(qty * price, 2)
        abgru = "02" if rng.random() < 0.02 else ""   # rejected item
        # Confirmed quantity from ATP
        short = short_supply.get(m[0], 0.05)
        r = rng.random()
        if abgru:
            bmeng = 0
        elif r < short * 0.25:
            bmeng = 0
        elif r < short:
            bmeng = max(1, int(qty * rng.uniform(0.3, 0.8))) if qty > 1 else 0
        else:
            bmeng = qty
        items.append(dict(posnr=posnr, matnr=m[0], qty=qty, uom=m[3], price=price,
                          netwr=netwr, abgru=abgru, bmeng=bmeng))
        vbap.append([vbeln, posnr, m[0], qty, m[3], f"{price:.2f}", f"{netwr:.2f}", PLANT, abgru])
        vbep.append([vbeln, posnr, "0001", fmt(edatu), qty, bmeng])

    head_netwr = round(sum(it["netwr"] for it in items if not it["abgru"]), 2)
    vbak.append([vbeln, fmt(erdat), "OR", VKORG, VTWEG, SPART, kunnr, f"{head_netwr:.2f}",
                 "USD", cmgst, fmt(credit_release), lifsk, faksk])

    # ------------------------------------------------ delivery
    if cmgst == "B" or lifsk:
        continue
    to_ship = [it for it in items if it["bmeng"] > 0]
    if not to_ship:
        continue
    ready = credit_release or erdat
    del_created = add_workdays(max(ready, add_workdays(edatu, -3)), rng.randint(0, 1))
    if del_created > CUTOFF:
        continue
    r = rng.random()
    if r < 0.70:
        gi_offset = rng.randint(-1, 0)
    elif r < 0.84:
        gi_offset = rng.randint(1, 2)
    else:
        gi_offset = rng.randint(3, 7)
    gi = add_workdays(edatu, gi_offset)
    if credit_release and gi < credit_release:
        gi = add_workdays(credit_release, 1)
    if gi < del_created:
        gi = del_created
    wadat_ist = gi if gi <= CUTOFF else None            # not yet goods-issued

    deliv_no += 1
    dvbeln = f"{deliv_no:010d}"
    likp.append([dvbeln, fmt(del_created), "LF", VSTEL, kunnr, fmt(edatu), fmt(wadat_ist)])
    for j, it in enumerate(to_ship, start=1):
        lips.append([dvbeln, f"{j * 10:06d}", it["matnr"], it["bmeng"], it["uom"], vbeln, it["posnr"]])

    # ------------------------------------------------ billing
    if not wadat_ist or faksk:
        continue
    fkdat = add_workdays(wadat_ist, rng.choices([0, 1, 2, 3, 6], weights=[45, 30, 12, 8, 5])[0])
    if fkdat > CUTOFF:
        continue

    def make_invoice(fkart, fkdat_, sfakn="", fksto=""):
        global bill_no
        bill_no += 1
        bv = f"{bill_no:010d}"
        total = 0.0
        for j, it in enumerate(to_ship, start=1):
            val = round(it["bmeng"] * it["price"], 2)
            total += val
            vbrp.append([bv, f"{j * 10:06d}", it["matnr"], it["bmeng"], it["uom"], f"{val:.2f}",
                         dvbeln, f"{j * 10:06d}", vbeln, it["posnr"]])
        vbrk.append([bv, fkart, fmt(fkdat_), kunnr, f"{round(total, 2):.2f}", "USD", fksto, sfakn])
        return bv

    if rng.random() < 0.015:
        # Invoice posted with an error, cancelled (S1) and re-billed
        orig = make_invoice("F2", fkdat)
        vbrk[-1][6] = "X"
        canc_date = add_workdays(fkdat, rng.randint(1, 3))
        if canc_date <= CUTOFF:
            make_invoice("S1", canc_date, sfakn=orig)
            rebill = add_workdays(canc_date, rng.randint(0, 1))
            if rebill <= CUTOFF:
                make_invoice("F2", rebill)
        else:
            vbrk[-1][6] = ""
    else:
        make_invoice("F2", fkdat)


def dump(name, header, rows):
    with open(out / f"{name}.csv", "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


dump("VBAK", ["VBELN", "ERDAT", "AUART", "VKORG", "VTWEG", "SPART", "KUNNR", "NETWR", "WAERK",
              "CMGST", "CREDIT_RELEASE_DATE", "LIFSK", "FAKSK"], vbak)
dump("VBAP", ["VBELN", "POSNR", "MATNR", "KWMENG", "VRKME", "NETPR", "NETWR", "WERKS", "ABGRU"], vbap)
dump("VBEP", ["VBELN", "POSNR", "ETENR", "EDATU", "WMENG", "BMENG"], vbep)
dump("LIKP", ["VBELN", "ERDAT", "LFART", "VSTEL", "KUNAG", "LFDAT", "WADAT_IST"], likp)
dump("LIPS", ["VBELN", "POSNR", "MATNR", "LFIMG", "VRKME", "VGBEL", "VGPOS"], lips)
dump("VBRK", ["VBELN", "FKART", "FKDAT", "KUNRG", "NETWR", "WAERK", "FKSTO", "SFAKN"], vbrk)
dump("VBRP", ["VBELN", "POSNR", "MATNR", "FKIMG", "VRKME", "NETWR", "VGBEL", "VGPOS", "AUBEL", "AUPOS"], vbrp)

print(f"Orders {len(vbak)}, items {len(vbap)}, deliveries {len(likp)}, "
      f"delivery items {len(lips)}, billing docs {len(vbrk)}, billing items {len(vbrp)}")
print(f"Files written to {out}")
