# Getting Data Ready

To run simulations for a specific country or region, the system expects data to be organized in a standardized format within the `data/` directory. This design allows the code to be country-agnostic.

## Directory Structure

Create a subdirectory for your country (e.g., `data/my_country/`) with the following structure:

```
data/my_country/
├── municipalities.csv       # Standardized municipality data
├── regions.geojson          # Polygon boundaries for municipalities
├── cities.csv               # Major cities for map visualization
└── opencellid/
    └── xxx.csv              # OpenCellID gNB data (e.g., 214.csv, 311.csv)
```

## Required Files

### 1. `municipalities.csv`
Contains the list of administrative regions (municipalities, counties, etc.) where agents will be distributed.

**Format:** CSV with headers.
**Columns:**
*   `id`: Unique identifier (String). Must match the `id` property in the GeoJSON.
*   `name`: Name of the municipality.
*   `population`: Integer population count.
*   `lat`: Latitude of the centroid.
*   `lon`: Longitude of the centroid.

### 2. `regions.geojson`
Contains the geometric boundaries of the municipalities. Used for accurate agent placement within borders.

*   **Format:** Standard GeoJSON FeatureCollection.
*   **Properties:** Each feature must have an `id` property that corresponds to the `id` in `municipalities.csv`.

### 3. `cities.csv`
Contains a list of major cities to be plotted as "stars" on the topology map for reference.

**Format:** CSV with headers.
**Columns:**
*   `name`: Name of the city.
*   `lat`: Latitude.
*   `lon`: Longitude.

### 4. OpenCellID Data
Download the cell tower data for your country (MCC) from [OpenCellID](https://opencellid.org/). Place the CSV file inside the `opencellid/` folder.

## Helper Scripts

We provide Python scripts to help convert raw data sources (like INE for Spain or Census Bureau for USA) into this standard format. These scripts are located in the `data/` directory.

*   `data/standardize_spain.py`: Converts Spanish INE data.
*   `data/standardize_usa.py`: Converts US Census data.

You can use these as templates to write a converter for other data sources.
