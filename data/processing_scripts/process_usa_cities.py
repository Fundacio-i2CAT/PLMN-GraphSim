import pandas as pd
import os

# Define paths
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Go up one level to 'data'
DATA_DIR = os.path.dirname(CURRENT_DIR)
DATA_USA_DIR = os.path.join(DATA_DIR, 'usa')

AGENTS_DIR = os.path.join(DATA_USA_DIR, 'agent-unprocessed-raw-datasets')
INPUT_CSV = os.path.join(AGENTS_DIR, 'uscities.csv')
OUTPUT_CSV = os.path.join(DATA_USA_DIR, 'usa_cities.csv')

def process_cities():
    print("Loading US Cities...")
    try:
        df = pd.read_csv(INPUT_CSV)
    except FileNotFoundError:
        print(f"Error: {INPUT_CSV} not found.")
        return

    print(f"Loaded {len(df)} cities.")
    
    # Filter for major cities
    # Criteria: 
    # 1. State capitals (capital == 'primary' or similar? Let's check columns)
    # 2. Population > Threshold (e.g. 500,000)
    
    # Let's inspect columns first (conceptually)
    # Usually simplemaps has: city, state_id, state_name, lat, lng, population, density, source, military, incorporated, timezone, ranking, zips, id
    
    # We want a good distribution.
    # Let's take the top 50 cities by population
    top_pop = df.sort_values(by='population', ascending=False).head(50)
    
    # And also include state capitals if not already in top 50
    # 'capital' column usually has 'primary' for state capital? Or maybe it's not in the basic file?
    # The basic file usually has 'capital' column where 'admin' is state capital?
    # Let's assume 'population' is the main driver for "stars" on a map for now.
    # If we want state capitals, we might need to look for a specific column.
    
    # Let's just stick to top 50 most populous cities for simplicity and coverage.
    # Or maybe top 2 per state to ensure coverage?
    
    # Let's try to get at least one city per state (the most populous one)
    # plus the overall top 20.
    
    top_per_state = df.loc[df.groupby('state_id')['population'].idxmax()]
    
    combined = pd.concat([top_pop, top_per_state]).drop_duplicates()
    
    print(f"Selected {len(combined)} cities (Top 50 + Top per state).")
    
    # Select columns
    result = combined[['city', 'lat', 'lng']].copy()
    result.rename(columns={'city': 'name', 'lng': 'lon'}, inplace=True)
    
    result.to_csv(OUTPUT_CSV, index=False)
    print(f"Saved to {OUTPUT_CSV}")

if __name__ == "__main__":
    process_cities()
