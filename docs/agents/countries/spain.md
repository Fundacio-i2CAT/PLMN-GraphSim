* **`data/214.csv`**: Contains **Cell Tower (gNB) locations** for Spain (MCC 214).
  * *Source*: [OpenCellID](https://opencellid.org/).
* **`data/municipalities_coordinates.csv`**: Essential for **population data** (used to distribute agents realistically) and municipality centroids.
  * *Source*: CNIG (Centro Nacional de Información Geográfica) via [Datos Abiertos del CNIG](https://centrodedescargas.cnig.es/CentroDescargas/nomenclator-geografico-municipios-entidades-poblacion).
* **`data/esri_municipios.geojson`**: Essential for **geometric boundaries** (polygons), used to verify if agents are located within valid municipality borders.
  * *Source*: [IGN (Instituto Geográfico Nacional)](https://opendata.esri.es/datasets/municipios-ign).

Both municipality files are required because the GeoJSON lacks population statistics, while the CSV lacks the polygon shapes needed for spatial containment checks.
