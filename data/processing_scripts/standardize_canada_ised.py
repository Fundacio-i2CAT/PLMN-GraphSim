"""Build an official Canadian base-station field from the ISED site data extract.

Canadian cellular spectrum is licensed by area rather than per transmitter, but
licensees must still upload the sites they operate under those licences. ISED
publishes the result as the Terrestrial Spectrum Licence Site Data Extract,
distributed as Site_Data_Extract_FX.zip:

  https://ised-isde.canada.ca/site/spectrum-management-system/en/download-sms-data

Do not confuse it with the Technical and Administrative Frequency List
(TAFL_LandMobile), which covers private land mobile radio and contains almost no
carrier cell sites. This file is the Canadian counterpart of the FCC Antenna
Structure Registry and of the French ANFR BNIR export.

One row is a licence, frequency and site combination, so a site appears many
times. Sites are deduplicated on rounded coordinates per operator.

Output: data/canada/ised/302.csv in the 14-column OpenCellID layout, tagged with
each carrier's MNC so it can be compared operator by operator.

Run: python3 standardize_canada_ised.py
"""

import csv
import os
import sys

csv.field_size_limit(10_000_000)

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
CA_DIR = os.path.join(DATA_DIR, "canada")
RAW = os.path.join(CA_DIR, "agent-unprocessed-raw-datasets", "Site_Data_Extract_FX.csv")
OUT_DIR = os.path.join(CA_DIR, "ised")

# Licensee name fragment -> (MNC, label). Telus files under two account names and
# Fido is a Rogers brand sharing its network.
CARRIERS = [
    ("telus", 220, "Telus"),
    ("bell mobility", 610, "Bell Mobility"),
    ("rogers", 720, "Rogers"),
    ("fido", 720, "Rogers"),
    ("vidéotron", 500, "Videotron"),
    ("videotron", 500, "Videotron"),
    ("sasktel", 780, "SaskTel"),
]


def carrier_of(name):
    low = name.lower()
    for frag, mnc, label in CARRIERS:
        if frag in low:
            return mnc, label
    return None, None


def main():
    if not os.path.isfile(RAW):
        sys.exit(f"missing {RAW}; unzip Site_Data_Extract_FX.zip there first")
    os.makedirs(OUT_DIR, exist_ok=True)

    seen, per_op, rows = set(), {}, 0
    with open(RAW, encoding="utf-8-sig", newline="") as fh:
        for rec in csv.DictReader(fh):
            rows += 1
            mnc, label = carrier_of((rec.get("licensee_name*") or "").strip())
            if mnc is None:
                continue
            try:
                lat = round(float(rec["latitude"]), 5)
                lon = round(float(rec["longitude"]), 5)
            except (KeyError, TypeError, ValueError):
                continue
            if not (41.0 <= lat <= 84.0 and -142.0 <= lon <= -52.0):
                continue
            key = (mnc, lat, lon)
            if key in seen:
                continue
            seen.add(key)
            per_op[label] = per_op.get(label, 0) + 1

    out = os.path.join(OUT_DIR, "302.csv")
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        for i, (mnc, lat, lon) in enumerate(sorted(seen), start=1):
            w.writerow(["LTE", 302, mnc, 0, i, 0, lon, lat, 1000, 1, 0, 0, 0, 0])

    print(f"  extract rows read: {rows:,}")
    print(f"  distinct carrier sites: {len(seen):,}")
    for label, n in sorted(per_op.items(), key=lambda kv: -kv[1]):
        print(f"    {label:16} {n:,}")
    print(f"  wrote {out}")


if __name__ == "__main__":
    main()
