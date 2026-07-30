"""Build Canada inputs for PLMN-GraphSim from Statistics Canada open data.

Sources, both 2021 Census:
  - lcsd000b21a_e: cartographic boundary file, census subdivisions (CSD),
    NAD83 Statistics Canada Lambert (EPSG:3347)
  - 98100002.csv: population and dwelling counts, joined on DGUID

CSDs are Canada's municipal level and are the counterpart of Spanish municipios
and US counties in the other scenarios. Geometry is reprojected to WGS84 and
simplified, because the simulator only needs polygons for rejection sampling
when placing agents.

Outputs:
  data/canada/municipalities.csv  id,name,population,lat,lon
  data/canada/regions.geojson     FeatureCollection, properties.id == CSV id
  data/canada/cities.csv          name,lat,lon for the largest subdivisions

Run: python3 standardize_canada.py
"""

import csv
import json
import os

import shapefile
from pyproj import Transformer
from shapely.geometry import mapping, shape
from shapely.ops import transform as shp_transform

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
CA_DIR = os.path.join(DATA_DIR, "canada")
RAW_DIR = os.path.join(CA_DIR, "agent-unprocessed-raw-datasets")
SHP = os.path.join(RAW_DIR, "lcsd000b21a_e")
POP_CSV = os.path.join(RAW_DIR, "98100002.csv")

SIMPLIFY_TOLERANCE_DEG = 0.002  # about 200 m
N_CITIES = 60


def norm_id(code):
    code = str(code).strip()
    return str(int(code)) if code.isdigit() else code


def load_population():
    """DGUID -> 2021 population, for census subdivisions only."""
    pops = {}
    with open(POP_CSV, encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        pop_key = next(k for k in reader.fieldnames if "Population, 2021" in k)
        for row in reader:
            dguid = (row.get("DGUID") or "").strip()
            raw = (row.get(pop_key) or "").strip().replace(",", "")
            if not dguid or not raw.isdigit():
                continue
            # CSD DGUIDs carry schema 2021A0005 followed by the 7-digit CSDUID
            if "A0005" not in dguid:
                continue
            pops[dguid] = int(raw)
    print(f"  population rows for CSDs: {len(pops)}")
    return pops


def main():
    pops = load_population()
    to_wgs84 = Transformer.from_crs("EPSG:3347", "EPSG:4326", always_xy=True).transform

    # The StatCan dbf carries accented French names in latin-1.
    reader = shapefile.Reader(SHP, encoding="latin-1")
    munis, features, missing = [], [], 0

    for sr in reader.iterShapeRecords():
        rec = sr.record.as_dict()
        csduid = str(rec.get("CSDUID", "")).strip()
        dguid = str(rec.get("DGUID", "")).strip()
        pop = pops.get(dguid)
        if pop is None:
            missing += 1
            continue
        if pop <= 0 or sr.shape is None:
            continue

        geom = shp_transform(to_wgs84, shape(sr.shape.__geo_interface__))
        simple = geom.simplify(SIMPLIFY_TOLERANCE_DEG, preserve_topology=True)
        if simple.is_empty:
            simple = geom
        centroid = simple.representative_point()

        mid = norm_id(csduid)
        munis.append(
            {
                "id": mid,
                "name": str(rec.get("CSDNAME", "Unknown")).strip(),
                "population": pop,
                "lat": round(centroid.y, 6),
                "lon": round(centroid.x, 6),
            }
        )
        features.append(
            {"type": "Feature", "properties": {"id": mid}, "geometry": mapping(simple)}
        )

    print(f"  subdivisions kept: {len(munis)} (no population match: {missing})")
    print(f"  total population: {sum(m['population'] for m in munis):,}")

    munis.sort(key=lambda r: r["id"])
    with open(os.path.join(CA_DIR, "municipalities.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["id", "name", "population", "lat", "lon"])
        w.writeheader()
        w.writerows(munis)

    path = os.path.join(CA_DIR, "regions.geojson")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"type": "FeatureCollection", "features": features}, fh)
    print(f"  regions.geojson: {os.path.getsize(path) / 1e6:.1f} MB")

    cities = sorted(munis, key=lambda r: -r["population"])[:N_CITIES]
    with open(os.path.join(CA_DIR, "cities.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["name", "lat", "lon"])
        w.writeheader()
        for c in cities:
            w.writerow({"name": c["name"], "lat": c["lat"], "lon": c["lon"]})
    print("Canada inputs ready.")


if __name__ == "__main__":
    main()
