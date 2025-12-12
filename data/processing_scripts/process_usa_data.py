import geopandas as gpd
import pandas as pd
import os

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.dirname(CURRENT_DIR)
DATA_USA_DIR = os.path.join(DATA_DIR, "usa")
AGENTS_DIR = os.path.join(DATA_USA_DIR, "agent-unprocessed-raw-datasets")
SHP_PATH = os.path.join(
    AGENTS_DIR, "cb_2024_us_county_500k", "cb_2024_us_county_500k.shp"
)
CSV_PATH = os.path.join(AGENTS_DIR, "co-est2024-alldata.csv")
OUTPUT_GEOJSON = os.path.join(DATA_USA_DIR, "usa_counties.geojson")
OUTPUT_CSV = os.path.join(DATA_USA_DIR, "usa_municipalities_coordinates.csv")


def process_data():
    print("Loading Shapefile...")
    gdf = gpd.read_file(SHP_PATH)

    # Ensure we have the FIPS code.
    # Census shapefiles usually have 'GEOID' which is the 5-digit FIPS.
    # Or 'STATEFP' and 'COUNTYFP'.
    if "GEOID" in gdf.columns:
        gdf["FIPS"] = gdf["GEOID"]
    else:
        gdf["FIPS"] = gdf["STATEFP"] + gdf["COUNTYFP"]

    print(f"Loaded {len(gdf)} counties from Shapefile.")

    print("Loading Population CSV...")
    df = pd.read_csv(CSV_PATH, encoding="latin-1")  # Census files often use latin-1

    # Create FIPS column in CSV
    # STATE is numeric, pad to 2 chars. COUNTY is numeric, pad to 3 chars.
    df["STATE_STR"] = df["STATE"].astype(str).str.zfill(2)
    df["COUNTY_STR"] = df["COUNTY"].astype(str).str.zfill(3)
    df["FIPS"] = df["STATE_STR"] + df["COUNTY_STR"]
    # Filter for County level summaries (SUMLEV 050)
    df = df[df["SUMLEV"] == 50]
    # Select relevant columns
    # We use POPESTIMATE2023 as the population count
    pop_col = "POPESTIMATE2023"
    if pop_col not in df.columns:
        # Fallback to 2022 or 2020 if 2023 not found (though file name suggests 2024 data)
        possible_cols = [
            "POPESTIMATE2024",
            "POPESTIMATE2023",
            "POPESTIMATE2022",
            "POPESTIMATE2020",
        ]
        for col in possible_cols:
            if col in df.columns:
                pop_col = col
                break

    print(f"Using population column: {pop_col}")

    df_subset = df[["FIPS", "CTYNAME", "STNAME", pop_col]].copy()
    df_subset.rename(
        columns={pop_col: "population", "CTYNAME": "name", "STNAME": "state_name"},
        inplace=True,
    )
    print(f"Loaded {len(df_subset)} counties from CSV.")
    print("Merging data...")
    # Merge GeoDataFrame with DataFrame
    merged_gdf = gdf.merge(df_subset, on="FIPS", how="left")

    # Check for unmerged
    missing = merged_gdf[merged_gdf["population"].isna()]
    if not missing.empty:
        print(f"Warning: {len(missing)} counties have no population data.")
        # print(missing[['FIPS', 'NAME']].head())
    merged_gdf["population"] = merged_gdf["population"].fillna(0).astype(int)

    # Ensure CRS is WGS84
    if merged_gdf.crs != "EPSG:4326":
        print("Reprojecting to EPSG:4326...")
        merged_gdf = merged_gdf.to_crs("EPSG:4326")

    print("Saving GeoJSON...")
    # Save only necessary columns to keep file size down
    # We keep geometry, FIPS, name, population
    cols_to_keep = ["FIPS", "name", "state_name", "population", "geometry"]
    final_gdf = merged_gdf[cols_to_keep]
    final_gdf.to_file(OUTPUT_GEOJSON, driver="GeoJSON")
    print(f"Saved to {OUTPUT_GEOJSON}")

    print("Calculating centroids and saving CSV...")
    # Let's just use the WGS84 centroids.
    centroids = final_gdf.geometry.centroid
    coords_df = pd.DataFrame(
        {
            "id": final_gdf["FIPS"],
            "name": final_gdf["name"],
            "population": final_gdf["population"],
            "lat": centroids.y,
            "lon": centroids.x,
        }
    )
    coords_df.to_csv(OUTPUT_CSV, index=False)
    print(f"Saved to {OUTPUT_CSV}")


if __name__ == "__main__":
    process_data()
