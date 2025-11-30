import shutil
import os
import pandas as pd

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
USA_DIR = os.path.join(DATA_DIR, "usa")
MUNI_INPUT = os.path.join(USA_DIR, "usa_municipalities_coordinates.csv")
GEOJSON_INPUT = os.path.join(USA_DIR, "usa_counties.geojson")
CITIES_INPUT = os.path.join(USA_DIR, "usa_cities.csv")
MUNI_OUTPUT = os.path.join(USA_DIR, "municipalities.csv")
GEOJSON_OUTPUT = os.path.join(USA_DIR, "regions.geojson")
CITIES_OUTPUT = os.path.join(USA_DIR, "cities.csv")


def standardize_usa():
    print("Standardizing USA Data...")
    df = pd.read_csv(MUNI_INPUT)
    # Filter for CONUS (Contiguous US)
    # Exclude Alaska (Lat > 50 approx) and Hawaii (Lon < -150 approx)
    print(
        f"Filtering for CONUS (Lat 24-50, Lon -125 to -66)... Original count: {len(df)}"
    )
    df = df[
        (df["lat"] > 24.0)
        & (df["lat"] < 50.0)
        & (df["lon"] > -125.0)
        & (df["lon"] < -66.0)
    ]
    print(f"Count after filtering: {len(df)}")
    df.to_csv(MUNI_OUTPUT, index=False)
    print(f"Copied municipalities to {MUNI_OUTPUT}")
    import json

    with open(GEOJSON_INPUT, "r") as f:
        data = json.load(f)
    for feature in data["features"]:
        props = feature["properties"]
        if "FIPS" in props:
            props["id"] = props["FIPS"]
    with open(GEOJSON_OUTPUT, "w") as f:
        json.dump(data, f)
    print(f"Saved GeoJSON to {GEOJSON_OUTPUT}")
    df_cities = pd.read_csv(CITIES_INPUT)
    df_cities.to_csv(CITIES_OUTPUT, index=False)
    print(f"Copied cities to {CITIES_OUTPUT}")


if __name__ == "__main__":
    standardize_usa()
