import pandas as pd
import os
import json

# Paths
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Go up one level to 'data'
DATA_DIR = os.path.dirname(CURRENT_DIR)
SPAIN_DIR = os.path.join(DATA_DIR, 'spain')
AGENTS_DIR = os.path.join(SPAIN_DIR, 'agent-unprocessed-raw-datasets')

# Input Files
MUNI_INPUT = os.path.join(AGENTS_DIR, 'municipalities_coordinates.csv')
GEOJSON_INPUT = os.path.join(AGENTS_DIR, 'esri_municipios.geojson')

# Output Files
MUNI_OUTPUT = os.path.join(SPAIN_DIR, 'municipalities.csv')
GEOJSON_OUTPUT = os.path.join(SPAIN_DIR, 'regions.geojson')
CITIES_OUTPUT = os.path.join(SPAIN_DIR, 'cities.csv')

def standardize_municipalities():
    print("Standardizing Spain Municipalities...")
    # Read with semicolon delimiter and comma decimal
    df = pd.read_csv(MUNI_INPUT, sep=';', decimal=',', encoding='latin-1')
    
    # Process Columns
    # COD_INE is 11 digits, we need first 5
    df['id'] = df['COD_INE'].astype(str).str.zfill(11).str[:5]
    
    # Rename and Select
    df = df.rename(columns={
        'NOMBRE_ACTUAL': 'name',
        'POBLACION_MUNI': 'population',
        'LATITUD_ETRS89': 'lat',
        'LONGITUD_ETRS89': 'lon'
    })
    
    # Handle missing population
    df['population'] = df['population'].fillna(0).astype(int)
    
    # Filter valid coordinates
    df = df[(df['lat'] != 0) & (df['lon'] != 0)]
    
    # Select final columns
    final_df = df[['id', 'name', 'population', 'lat', 'lon']]
    
    final_df.to_csv(MUNI_OUTPUT, index=False)
    print(f"Saved {len(final_df)} municipalities to {MUNI_OUTPUT}")

def standardize_geojson():
    print("Standardizing Spain GeoJSON...")
    # Just copy/rename, but maybe ensure ID property is standard?
    # The current loader looks for CODIGOINE. Let's standardize to 'id'.
    
    with open(GEOJSON_INPUT, 'r') as f:
        data = json.load(f)
    
    for feature in data['features']:
        props = feature['properties']
        if 'CODIGOINE' in props:
            props['id'] = props['CODIGOINE']
            # Optional: Clean up other props to save space
    
    with open(GEOJSON_OUTPUT, 'w') as f:
        json.dump(data, f)
    print(f"Saved GeoJSON to {GEOJSON_OUTPUT}")

def create_cities_csv():
    print("Creating Spain Cities CSV...")
    # Hardcoded list from Types.jl to CSV
    cities = [
        ("Madrid", 40.4168, -3.7038),
        ("Barcelona", 41.3851, 2.1734),
        ("Valencia", 39.4699, -0.3763),
        ("Seville", 37.3891, -5.9845),
        ("Zaragoza", 41.6488, -0.8891),
        ("Málaga", 36.7212, -4.4217),
        ("Murcia", 37.9922, -1.1307),
        ("Palma", 39.5696, 2.6502),
        ("Bilbao", 43.2630, -2.9350),
        ("Alicante", 38.3452, -0.4810),
        ("Córdoba", 37.8882, -4.7794),
        ("Valladolid", 41.6523, -4.7245),
        ("Vigo", 42.2406, -8.7207),
        ("Gijón", 43.5322, -5.6611),
        ("A Coruña", 43.3623, -8.4115),
        ("Vitoria", 42.8467, -2.6716),
        ("Granada", 37.1773, -3.5986),
        ("Oviedo", 43.3619, -5.8494),
        ("Pamplona", 42.8125, -1.6458),
        ("Almería", 36.8340, -2.4637),
        ("San Sebastián", 43.3183, -1.9812),
        ("Burgos", 42.3439, -3.6969),
        ("Santander", 43.4623, -3.8099),
        ("Castellón", 39.9864, -0.0513),
        ("Albacete", 38.9943, -1.8585),
        ("Logroño", 42.4623, -2.4449),
        ("Badajoz", 38.8794, -6.9706),
        ("Salamanca", 40.9701, -5.6635),
        ("Huelva", 37.2614, -6.9447),
        ("Lleida", 41.6176, 0.6200),
        ("Tarragona", 41.1189, 1.2445),
        ("León", 42.5987, -5.5671),
        ("Cádiz", 36.5271, -6.2886),
        ("Jaén", 37.7749, -3.7902),
        ("Ourense", 42.3358, -7.8639),
        ("Lugo", 43.0125, -7.5558),
        ("Girona", 41.9794, 2.8214),
        ("Cáceres", 39.4753, -6.3723),
        ("Santiago", 42.8782, -8.5448),
        ("Toledo", 39.8628, -4.0273),
        ("Guadalajara", 40.6328, -3.1602),
        ("Cuenca", 40.0704, -2.1374),
        ("Ciudad Real", 38.9848, -3.9274),
        ("Zamora", 41.5063, -5.7446),
        ("Palencia", 42.0095, -4.5286),
        ("Segovia", 40.9429, -4.1088),
        ("Soria", 41.7640, -2.4688),
        ("Teruel", 40.3456, -1.1065),
        ("Huesca", 42.1361, -0.4087),
        ("Ávila", 40.6565, -4.6813),
        ("Ceuta", 35.8894, -5.3213),
        ("Melilla", 35.2923, -2.9381)
    ]
    
    df = pd.DataFrame(cities, columns=['name', 'lat', 'lon'])
    df.to_csv(CITIES_OUTPUT, index=False)
    print(f"Saved {len(df)} cities to {CITIES_OUTPUT}")

if __name__ == "__main__":
    standardize_municipalities()
    standardize_geojson()
    create_cities_csv()
