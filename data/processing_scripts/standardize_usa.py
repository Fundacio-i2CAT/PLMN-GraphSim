import shutil
import os
import pandas as pd

# Paths
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Go up one level to 'data'
DATA_DIR = os.path.dirname(CURRENT_DIR)
USA_DIR = os.path.join(DATA_DIR, 'usa')

# Input Files
MUNI_INPUT = os.path.join(USA_DIR, 'usa_municipalities_coordinates.csv')
GEOJSON_INPUT = os.path.join(USA_DIR, 'usa_counties.geojson')
CITIES_INPUT = os.path.join(USA_DIR, 'usa_cities.csv')

# Output Files
MUNI_OUTPUT = os.path.join(USA_DIR, 'municipalities.csv')
GEOJSON_OUTPUT = os.path.join(USA_DIR, 'regions.geojson')
CITIES_OUTPUT = os.path.join(USA_DIR, 'cities.csv')

def standardize_usa():
    print("Standardizing USA Data...")
    
    # Municipalities
    # Check columns
    df = pd.read_csv(MUNI_INPUT)
    # Columns are: id,name,population,lat,lon
    # This is already standard. Just copy.
    df.to_csv(MUNI_OUTPUT, index=False)
    print(f"Copied municipalities to {MUNI_OUTPUT}")
    
    # GeoJSON
    # Just copy/rename. The processing script already put 'id' (FIPS) in properties?
    # Let's check. The script did: final_gdf = merged_gdf[['FIPS', 'name', ...]]
    # GeoJSON driver usually puts these in properties.
    # But let's ensure 'id' property exists for consistency with Spain.
    # Actually, let's just copy it for now. The loader can look for 'FIPS' or 'id'.
    # Better: Let's make the loader look for 'id' primarily, so let's ensure 'id' is in properties.
    
    import json
    with open(GEOJSON_INPUT, 'r') as f:
        data = json.load(f)
    
    for feature in data['features']:
        props = feature['properties']
        if 'FIPS' in props:
            props['id'] = props['FIPS']
    
    with open(GEOJSON_OUTPUT, 'w') as f:
        json.dump(data, f)
    print(f"Saved GeoJSON to {GEOJSON_OUTPUT}")
    
    # Cities
    # Columns: name,lat,lon. Already standard.
    df_cities = pd.read_csv(CITIES_INPUT)
    df_cities.to_csv(CITIES_OUTPUT, index=False)
    print(f"Copied cities to {CITIES_OUTPUT}")

if __name__ == "__main__":
    standardize_usa()
