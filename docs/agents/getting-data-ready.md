# Getting Data Ready

To run simulations for a specific country or region, the system expects data to be organized in a standardized format within the `data/` directory. This design allows the code to be country-agnostic.

## Directory Structure

Create a subdirectory for your country (e.g., `data/my_country/`) with the following structure:

```source
data/my_country/
├── municipalities.csv       # Standardized municipality data
├── regions.geojson          # Polygon boundaries for municipalities
├── cities.csv               # Major cities for map visualization
└── opencellid/
    └── xxx.csv              # OpenCellID gNB data (e.g., 214.csv, 311.csv)
```

## Country-Specific Files

Every country has its own data sources. For example, in Spain it is typically the INE (Instituto Nacional de Estadística) and in the USA it is the Census Bureau. The goal is to convert the raw country-specific data into this custom standard format defined in the simulator.

### 1. `municipalities.csv`

Contains the list of administrative regions (municipalities, counties, etc.) where agents will be distributed.

!!! info "Format Specification"
    **Format:** CSV with headers.
    
    **Columns:**

    * `id`: Unique identifier (String). **Must match the `id` property in the GeoJSON.**
    * `name`: Name of the municipality.
    * `population`: Integer population count.
    * `lat`: Latitude of the centroid.
    * `lon`: Longitude of the centroid.

### 2. `regions.geojson`

Contains the geometric boundaries of the municipalities. Used for accurate agent placement within borders.

!!! info "Format Specification"
    * **Format:** Standard GeoJSON FeatureCollection.
    * **Properties:** Each feature must have an `id` property that corresponds to the `id` in `municipalities.csv`.

!!! warning "Important"
    The `id` in `regions.geojson` must strictly match the `id` in `municipalities.csv` to ensure agents are correctly placed in their respective regions.

### 3. `cities.csv`

Contains a list of major cities to be plotted as "stars" on the topology map for reference.

!!! info "Format Specification"
    **Format:** CSV with headers.
    
    **Columns:**

    * `name`: Name of the city.
    * `lat`: Latitude.
    * `lon`: Longitude.

### 4. OpenCellID Data

Download the cell tower data for your country (MCC) from [OpenCellID](https://opencellid.org/). Place the CSV file inside the `opencellid/` folder.

## Helper Scripts

We provide scripts used to convert raw country-specific data into the standardized format required by the simulator. Check the country-specific documentation for details on how to use them.
