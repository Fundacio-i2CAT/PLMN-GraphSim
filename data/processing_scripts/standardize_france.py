"""Build France inputs for PLMN-GraphSim from official open data.

Sources (both served by Etalab's geo.api.gouv.fr, which republishes INSEE
population and IGN ADMIN-EXPRESS geometry):
  - commune list with legal population and centroid
  - commune contours, fetched per department

Scope: metropolitan France (departments 01-95 plus Corsica 2A/2B). Overseas
departments are excluded so that the simulated field is one contiguous landmass,
the same cut applied to mainland Portugal.

Outputs, matching the schema the simulator expects:
  data/france/municipalities.csv  id,name,population,lat,lon
  data/france/regions.geojson     FeatureCollection, properties.id == CSV id
  data/france/cities.csv          name,lat,lon for the largest communes

Municipality ids are written with leading zeros stripped on both sides, because
the loader normalizes any integer-looking id through parse(Int, .) and would
otherwise fail to join "01001" against 1001.

Run: python3 standardize_france.py
"""

import csv
import json
import os
import time
import urllib.request

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
FR_DIR = os.path.join(DATA_DIR, "france")
RAW_DIR = os.path.join(FR_DIR, "agent-unprocessed-raw-datasets")

API = "https://geo.api.gouv.fr/communes"
DEPARTMENTS = [f"{d:02d}" for d in range(1, 96) if d != 20] + ["2A", "2B"]
SIMPLIFY_TOLERANCE_DEG = 0.002  # about 200 m, ample for rejection sampling
N_CITIES = 60


def norm_id(code):
    """Match the loader's id normalization: strip leading zeros when numeric."""
    return str(int(code)) if code.isdigit() else code


def fetch(url, attempts=4):
    for i in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=180) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as exc:  # transient API errors are common on bulk pulls
            if i == attempts - 1:
                raise
            print(f"    retry {i + 1} after {exc}")
            time.sleep(3 * (i + 1))


def build_municipalities():
    print("Fetching commune list with population and centroid...")
    rows = fetch(f"{API}?fields=nom,code,population,centre")
    out = []
    for c in rows:
        code = c.get("code", "")
        centre = c.get("centre") or {}
        coords = centre.get("coordinates")
        if not code or code.startswith(("97", "98")) or not coords:
            continue
        out.append(
            {
                "id": norm_id(code),
                "name": c.get("nom", "Unknown"),
                "population": int(c.get("population") or 0),
                "lat": coords[1],
                "lon": coords[0],
            }
        )
    out.sort(key=lambda r: r["id"])
    path = os.path.join(FR_DIR, "municipalities.csv")
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["id", "name", "population", "lat", "lon"])
        w.writeheader()
        w.writerows(out)
    print(f"  wrote {len(out)} communes to {path}")

    cities = sorted(out, key=lambda r: -r["population"])[:N_CITIES]
    cpath = os.path.join(FR_DIR, "cities.csv")
    with open(cpath, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["name", "lat", "lon"])
        w.writeheader()
        for c in cities:
            w.writerow({"name": c["name"], "lat": c["lat"], "lon": c["lon"]})
    print(f"  wrote {len(cities)} cities to {cpath}")
    return {r["id"] for r in out}


def build_regions(valid_ids):
    from shapely.geometry import mapping, shape

    features = []
    for dep in DEPARTMENTS:
        url = f"{API}?codeDepartement={dep}&fields=code&format=geojson&geometry=contour"
        fc = fetch(url)
        kept = 0
        for f in fc.get("features", []):
            code = (f.get("properties") or {}).get("code", "")
            mid = norm_id(code)
            if mid not in valid_ids or not f.get("geometry"):
                continue
            geom = shape(f["geometry"]).simplify(SIMPLIFY_TOLERANCE_DEG, preserve_topology=True)
            if geom.is_empty:
                geom = shape(f["geometry"])
            features.append(
                {
                    "type": "Feature",
                    "properties": {"id": mid},
                    "geometry": mapping(geom),
                }
            )
            kept += 1
        print(f"  dept {dep}: {kept} contours (total {len(features)})")

    path = os.path.join(FR_DIR, "regions.geojson")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"type": "FeatureCollection", "features": features}, fh)
    mb = os.path.getsize(path) / 1e6
    print(f"  wrote {len(features)} polygons to {path} ({mb:.1f} MB)")


if __name__ == "__main__":
    os.makedirs(RAW_DIR, exist_ok=True)
    ids = build_municipalities()
    build_regions(ids)
    print("France inputs ready.")
