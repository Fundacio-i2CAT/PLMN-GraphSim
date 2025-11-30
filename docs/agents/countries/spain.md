## Raw Country-Specific Data for Spain

* **`data/214.csv`**: Contains **Cell Tower (gNB) locations** for Spain (MCC 214).
  * *Source*: [OpenCellID](https://opencellid.org/).
* **`data/municipalities_coordinates.csv`**: Essential for **population data** (used to distribute agents realistically) and municipality centroids.
  * *Source*: CNIG (Centro Nacional de Información Geográfica) via [Datos Abiertos del CNIG](https://centrodedescargas.cnig.es/CentroDescargas/nomenclator-geografico-municipios-entidades-poblacion).
* **`data/esri_municipios.geojson`**: Essential for **geometric boundaries** (polygons), used to verify if agents are located within valid municipality borders.
  * *Source*: [IGN (Instituto Geográfico Nacional)](https://opendata.esri.es/datasets/municipios-ign).

Both municipality files are required because the GeoJSON lacks population statistics, while the CSV lacks the polygon shapes needed for spatial containment checks.


## Helper Script

To ensure the simulation can read these files correctly, we use a Python script to standardize the data formats (column names, coordinate systems, etc.).

### `data/processing_scripts/standardize_spain.py`

This script performs the following actions:

1. **Reads** the raw `municipalities_coordinates.csv`.
2. **Renames** columns to the standard format (`id`, `name`, `population`, `lat`, `lon`).
3. **Filters** out invalid coordinates and locations outside mainland Spain (e.g., Canary Islands) to focus the simulation.
4. **Reads** the `esri_municipios.geojson`.
5. **Ensures** each feature has a standard `id` property matching the CSV.
6. **Generates** a `cities.csv` file for plotting major cities.
7. **Saves** the processed files to `data/spain/`:
    * `municipalities.csv`
    * `regions.geojson`
    * `cities.csv`

### Environment Setup & Execution

To ensure reproducibility, use a dedicated Python virtual environment for these scripts.

1. Set up the Environment:

```bash
cd data/processing_scripts
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ../..  # Return to project root
```

2. Run the Script:

```bash
source data/processing_scripts/.venv/bin/activate
python3 data/processing_scripts/standardize_spain.py
```

