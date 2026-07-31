"""Build an official French base-station field from the ANFR BNIR export.

ANFR maintains the Base Nationale des Installations Radioelectriques, in which
every operator is legally required to declare each radio installation above
5 W. It is the French counterpart of the FCC Antenna Structure Registry already
used as the dense upper bound on the United States field.

Two differences from OpenCelliD matter for this study:
  - ANFR records are sites (one station per operator per support), whereas
    OpenCelliD records are cells, so one ANFR site corresponds to roughly three
    OpenCelliD rows for a three-sector deployment.
  - ANFR positions are declared by the operator, whereas every OpenCelliD
    position is a crowdsourced estimate.

Inputs, from the monthly export and the reference tables:
  SUP_SUPPORT.txt   support geometry, coordinates in degrees/minutes/seconds
  SUP_STATION.txt   station to operator (ADM_ID)
  SUP_EXPLOITANT.txt  ADM_ID to operator name

Output: data/france/anfr/208.csv in the 14-column OpenCelliD layout the loader
expects, tagged with the real MNC of each operator so the field can be compared
against the OpenCelliD one operator by operator.

Run: python3 standardize_france_anfr.py
"""

import csv
import os
import sys

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
FR_DIR = os.path.join(DATA_DIR, "france")
RAW_DIR = os.path.join(FR_DIR, "agent-unprocessed-raw-datasets", "anfr")
OUT_DIR = os.path.join(FR_DIR, "anfr")

# ANFR operator id -> (MNC used by OpenCelliD, label)
OPERATORS = {
    "23": (1, "Orange"),
    "137": (10, "SFR"),
    "240": (15, "Free Mobile"),
    "6": (20, "Bouygues Telecom"),
}

# Metropolitan France, matching the commune table built by standardize_france.py.
LAT_RANGE = (41.0, 51.5)
LON_RANGE = (-5.5, 10.0)


def dms(deg, minute, sec, hemi):
    try:
        v = float(deg) + float(minute) / 60.0 + float(sec) / 3600.0
    except (TypeError, ValueError):
        return None
    return -v if hemi in ("S", "W", "O") else v


def load_station_operators():
    """STA_NM_ANFR -> ADM_ID, keeping only the four mobile operators."""
    path = os.path.join(RAW_DIR, "SUP_STATION.txt")
    out = {}
    with open(path, encoding="latin-1") as fh:
        for row in csv.DictReader(fh, delimiter=";"):
            adm = row["ADM_ID"].strip()
            if adm in OPERATORS:
                out[row["STA_NM_ANFR"].strip()] = adm
    print(f"  mobile-operator stations: {len(out):,}")
    return out


def main():
    if not os.path.isdir(RAW_DIR):
        sys.exit(f"missing {RAW_DIR}; unzip the ANFR monthly export there first")
    os.makedirs(OUT_DIR, exist_ok=True)
    station_adm = load_station_operators()

    rows, per_op, skipped = [], {}, 0
    with open(os.path.join(RAW_DIR, "SUP_SUPPORT.txt"), encoding="latin-1") as fh:
        for rec in csv.DictReader(fh, delimiter=";"):
            adm = station_adm.get(rec["STA_NM_ANFR"].strip())
            if adm is None:
                continue
            lat = dms(rec["COR_NB_DG_LAT"], rec["COR_NB_MN_LAT"], rec["COR_NB_SC_LAT"], rec["COR_CD_NS_LAT"].strip())
            lon = dms(rec["COR_NB_DG_LON"], rec["COR_NB_MN_LON"], rec["COR_NB_SC_LON"], rec["COR_CD_EW_LON"].strip())
            if lat is None or lon is None:
                skipped += 1
                continue
            if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1] and LON_RANGE[0] <= lon <= LON_RANGE[1]):
                skipped += 1  # overseas departments, out of the modelled field
                continue
            mnc, label = OPERATORS[adm]
            per_op[label] = per_op.get(label, 0) + 1
            rows.append((mnc, round(lon, 6), round(lat, 6)))

    out_path = os.path.join(OUT_DIR, "208.csv")
    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        for i, (mnc, lon, lat) in enumerate(rows, start=1):
            # radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,avg
            w.writerow(["LTE", 208, mnc, 0, i, 0, lon, lat, 1000, 1, 0, 0, 0, 0])

    print(f"  sites written: {len(rows):,} (outside metropolitan France or unparsable: {skipped:,})")
    for label, n in sorted(per_op.items(), key=lambda kv: -kv[1]):
        print(f"    {label:20} {n:,}")
    print(f"  wrote {out_path}")


if __name__ == "__main__":
    main()
