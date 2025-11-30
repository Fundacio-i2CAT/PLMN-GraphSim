import pandas as pd
import os

# Define paths
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
# Go up one level to 'data'
DATA_DIR = os.path.dirname(CURRENT_DIR)
DATA_USA_DIR = os.path.join(DATA_DIR, "usa")

AGENTS_DIR = os.path.join(DATA_USA_DIR, "agent-unprocessed-raw-datasets")
INPUT_CSV = os.path.join(AGENTS_DIR, "uscities.csv")
OUTPUT_CSV = os.path.join(DATA_USA_DIR, "usa_cities.csv")


def process_cities():
    print("Loading US Cities...")
    try:
        df = pd.read_csv(INPUT_CSV)
    except FileNotFoundError:
        print(f"Error: {INPUT_CSV} not found.")
        return

    print(f"Loaded {len(df)} cities.")
    # Take the top 50 cities by population
    top_pop = df.sort_values(by="population", ascending=False).head(50)
    # And also include state capitals if not already in top 50
    top_per_state = df.loc[df.groupby("state_id")["population"].idxmax()]
    combined = pd.concat([top_pop, top_per_state]).drop_duplicates()
    print(f"Selected {len(combined)} cities (Top 50 + Top per state).")
    result = combined[["city", "lat", "lng"]].copy()
    result.rename(columns={"city": "name", "lng": "lon"}, inplace=True)
    result.to_csv(OUTPUT_CSV, index=False)
    print(f"Saved to {OUTPUT_CSV}")


if __name__ == "__main__":
    process_cities()
