"""Standardize Portugal data for the simulator (Iberia roaming scenario, phase 2).

Portugal's official sources mirror Spain's INE + IGN pair:

- **INE Portugal** (Instituto Nacional de Estatística, ine.pt) — resident population
  by municipality, **Censos 2021 definitive** (indicator 0011609, "População residente
  por Local de residência à data dos Censos [2021]"). Municipalities carry the 4-digit
  **DICO** code (district + concelho) in `geocod`.
  Raw: agent-unprocessed-raw-datasets/ine_censos2021.json, fetched from
  https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=0011609&lang=PT
- **DGT CAOP 2025** (Direção-Geral do Território, Carta Administrativa Oficial de
  Portugal) — official municipality polygons, mainland (Continente) only, keyed by the
  same DICO code (`dtmn`), WGS84 GeoJSON via the DGT OGC API.
  Raw: agent-unprocessed-raw-datasets/caop_municipios.json, fetched from
  https://ogcapi.dgterritorio.gov.pt/collections/municipios/items?f=json&limit=300
- **GeoNames PT.zip** (CC-BY-4.0) — only for cities.csv (map labels).

Join key: DICO (CAOP `dtmn` == INE `geocod` for the 4-digit municipality rows).
CAOP Continente is mainland-only (278 concelhos), so the islands cut (Madeira/Azores,
mirroring Spain's Canary filter) falls out of the join for free.

Outputs (simulator standard format, see docs/agents/getting-data-ready.md):
  ../portugal/municipalities.csv  id,name,population,lat,lon  (id = DICO; centroid from CAOP)
  ../portugal/regions.geojson     FeatureCollection, feature property id = DICO
  ../portugal/cities.csv          name,lat,lon

Dependency: shapely (polygon centroids). Usage:
  python standardize_portugal.py
"""

import csv
import json
import os

from shapely.geometry import shape

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
PT_DIR = os.path.join(DATA_DIR, "portugal")
RAW_DIR = os.path.join(PT_DIR, "agent-unprocessed-raw-datasets")
CAOP_INPUT = os.path.join(RAW_DIR, "caop_municipios.json")
INE_INPUT = os.path.join(RAW_DIR, "ine_censos2021.json")
GEONAMES_INPUT = os.path.join(RAW_DIR, "PT.txt")
MUNI_OUTPUT = os.path.join(PT_DIR, "municipalities.csv")
GEOJSON_OUTPUT = os.path.join(PT_DIR, "regions.geojson")
CITIES_OUTPUT = os.path.join(PT_DIR, "cities.csv")

MAINLAND_MIN_LON = -10.0  # cities filter only (CAOP is already mainland-only)
CITY_MIN_POPULATION = 100_000


def load_ine_population():
    """DICO -> Censos 2021 resident population (sex/age totals row)."""
    with open(INE_INPUT, encoding="utf-8") as f:
        payload = json.load(f)
    data = payload[0] if isinstance(payload, list) else payload
    rows = data["Dados"]["2021"]
    pop = {}
    for r in rows:
        if r.get("dim_3") == "T" and r.get("dim_4") == "T" and len(r["geocod"]) == 4:
            pop[r["geocod"]] = int(r["valor"])
    return pop


def standardize_municipalities():
    population = load_ine_population()
    with open(CAOP_INPUT, encoding="utf-8") as f:
        caop = json.load(f)

    municipalities = []
    features_out = []
    unmatched = []
    for feat in caop["features"]:
        dico = feat["properties"]["dtmn"]
        name = feat["properties"]["municipio"]
        if dico not in population:
            unmatched.append((dico, name))
            continue
        centroid = shape(feat["geometry"]).centroid
        municipalities.append((dico, name, population[dico], round(centroid.y, 6), round(centroid.x, 6)))
        features_out.append({
            "type": "Feature",
            "properties": {"id": dico, "name": name},
            "geometry": feat["geometry"],
        })

    if unmatched:
        print(f"WARNING: {len(unmatched)} CAOP municipalities without INE population: {unmatched}")

    municipalities.sort(key=lambda m: m[0])
    with open(MUNI_OUTPUT, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "name", "population", "lat", "lon"])
        w.writerows(municipalities)
    total = sum(m[2] for m in municipalities)
    print(f"Saved {len(municipalities)} mainland concelhos "
          f"(Censos 2021 population {total:,}) to {MUNI_OUTPUT}")

    with open(GEOJSON_OUTPUT, "w", encoding="utf-8") as f:
        json.dump({"type": "FeatureCollection", "features": features_out}, f)
    print(f"Saved {len(features_out)} polygons to {GEOJSON_OUTPUT}")
    return total


def standardize_cities():
    cities = []
    with open(GEONAMES_INPUT, encoding="utf-8") as f:
        for row in csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            lat, lon = float(row[4]), float(row[5])
            if lon <= MAINLAND_MIN_LON:
                continue
            population = int(row[14] or 0)
            if row[6] == "P" and population >= CITY_MIN_POPULATION:
                cities.append((row[1], lat, lon, population))
    cities.sort(key=lambda c: -c[3])
    with open(CITIES_OUTPUT, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["name", "lat", "lon"])
        w.writerows([(n, la, lo) for n, la, lo, _ in cities])
    print(f"Saved {len(cities)} cities (pop >= {CITY_MIN_POPULATION:,}) to {CITIES_OUTPUT}")


if __name__ == "__main__":
    standardize_municipalities()
    standardize_cities()
