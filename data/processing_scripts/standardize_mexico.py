"""Build Mexico inputs for PLMN-GraphSim from official open data.

Sources:
  - muni_2018gw: municipal boundaries, CONABIO republication of the INEGI
    Marco Geoestadistico, already in WGS84 geographic coordinates. Used instead
    of the raw INEGI bundle, which ships at 3.4 GB because it also carries
    block-level geometry this study does not need.
  - conjunto_de_datos_iter_00CSV20.csv: INEGI Censo 2020 ITER. Municipal totals
    are the rows with LOC == 0000, joined on the state and municipality keys.

Municipios are Mexico's municipal level, the counterpart of Spanish municipios
and US counties elsewhere in the evaluation.

Outputs:
  data/mexico/municipalities.csv  id,name,population,lat,lon
  data/mexico/regions.geojson     FeatureCollection, properties.id == CSV id
  data/mexico/cities.csv          name,lat,lon for the largest municipios

Run: python3 standardize_mexico.py
"""

import csv
import json
import os

import shapefile
from shapely.geometry import mapping, shape

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
MX_DIR = os.path.join(DATA_DIR, "mexico")
RAW_DIR = os.path.join(MX_DIR, "agent-unprocessed-raw-datasets")
SHP = os.path.join(RAW_DIR, "muni_2018gw")
ITER_CSV = os.path.join(RAW_DIR, "conjunto_de_datos_iter_00CSV20.csv")

SIMPLIFY_TOLERANCE_DEG = 0.002  # about 200 m
N_CITIES = 60


def norm_id(code):
    code = str(code).strip()
    return str(int(code)) if code.isdigit() else code


def load_population():
    """CVEGEO (state + municipality) -> 2020 municipal population."""
    pops, names = {}, {}
    with open(ITER_CSV, encoding="utf-8-sig") as fh:
        for row in csv.DictReader(fh):
            ent, mun, loc = row["ENTIDAD"].strip(), row["MUN"].strip(), row["LOC"].strip()
            if loc != "0000" or mun == "000":
                continue
            raw = row["POBTOT"].strip().replace(",", "")
            if not raw.isdigit():
                continue
            key = norm_id(f"{ent}{mun}")
            pops[key] = int(raw)
            names[key] = row["NOM_MUN"].strip()
    print(f"  municipal population rows: {len(pops)}, total {sum(pops.values()):,}")
    return pops, names


def main():
    pops, names = load_population()
    reader = shapefile.Reader(SHP, encoding="latin-1")
    munis, features, missing = [], [], 0

    for sr in reader.iterShapeRecords():
        rec = sr.record.as_dict()
        cvegeo = str(rec.get("CVEGEO", "")).strip()
        mid = norm_id(cvegeo)
        pop = pops.get(mid)
        if pop is None:
            missing += 1
            continue
        if pop <= 0 or sr.shape is None:
            continue

        geom = shape(sr.shape.__geo_interface__)
        simple = geom.simplify(SIMPLIFY_TOLERANCE_DEG, preserve_topology=True)
        if simple.is_empty:
            simple = geom
        centroid = simple.representative_point()

        munis.append(
            {
                "id": mid,
                "name": names.get(mid) or str(rec.get("NOM_MUN", "Unknown")).strip(),
                "population": pop,
                "lat": round(centroid.y, 6),
                "lon": round(centroid.x, 6),
            }
        )
        features.append(
            {"type": "Feature", "properties": {"id": mid}, "geometry": mapping(simple)}
        )

    print(f"  municipios kept: {len(munis)} (no population match: {missing})")
    print(f"  covered population: {sum(m['population'] for m in munis):,}")

    munis.sort(key=lambda r: int(r["id"]) if r["id"].isdigit() else 0)
    with open(os.path.join(MX_DIR, "municipalities.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["id", "name", "population", "lat", "lon"])
        w.writeheader()
        w.writerows(munis)

    path = os.path.join(MX_DIR, "regions.geojson")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"type": "FeatureCollection", "features": features}, fh)
    print(f"  regions.geojson: {os.path.getsize(path) / 1e6:.1f} MB")

    cities = sorted(munis, key=lambda r: -r["population"])[:N_CITIES]
    with open(os.path.join(MX_DIR, "cities.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["name", "lat", "lon"])
        w.writeheader()
        for c in cities:
            w.writerow({"name": c["name"], "lat": c["lat"], "lon": c["lon"]})
    print("Mexico inputs ready.")


if __name__ == "__main__":
    main()
