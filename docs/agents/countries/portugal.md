# Raw Country-Specific Data for Portugal

Portugal exists for the **Iberia roaming scenario** (phase 2 of the §7.4 roaming work):
a Spanish home operator's subscribers roaming into a Portuguese visited network across a
real land border, giving geometric border crossings and a realistic Home-Routed hairpin
(Lisbon serving site → Madrid PSA).

Portugal's official sources mirror Spain's INE + IGN pair exactly — Portugal's national
statistics institute is also called **INE** (Instituto Nacional de Estatística,
[ine.pt](https://www.ine.pt)), and the boundary authority is the **DGT**
(Direção-Geral do Território) via the **CAOP** (Carta Administrativa Oficial de
Portugal).

* **`opencellid/268.csv`**: Cell Tower (gNB) locations for Portugal (MCC 268), 22,627
  cells.
  * *Source*: [OpenCellID](https://opencellid.org/) (MCC-268 extract, retrieved
    July 2026).
* **`agent-unprocessed-raw-datasets/ine_censos2021.json`**: resident population per
  municipality, **Censos 2021 definitive** (indicator 0011609, "População residente por
  Local de residência à data dos Censos [2021]"). Municipality rows carry the official
  4-digit **DICO** code.
  * *Source*: [INE Portugal JSON API](https://www.ine.pt/ine/json_indicador/pindica.jsp?op=2&varcd=0011609&lang=PT).
* **`agent-unprocessed-raw-datasets/caop_municipios.json`**: official municipality
  polygons, **CAOP2025 Continente** (mainland only), WGS84 GeoJSON, keyed by the same
  DICO code (`dtmn`).
  * *Source*: [DGT OGC API](https://ogcapi.dgterritorio.gov.pt/collections/municipios/items?f=json&limit=300)
    (dataset registered at [dados.gov.pt](https://dados.gov.pt/pages/datasets/carta-administrativa-oficial-de-portugal-caop2025-continente)).
* **`agent-unprocessed-raw-datasets/PT.txt`**: GeoNames country dump
  ([PT.zip](https://download.geonames.org/export/dump/PT.zip), CC-BY-4.0) — used only
  for `cities.csv` map labels.

## Helper Script

### `data/processing_scripts/standardize_portugal.py`

Joins INE population to CAOP polygons on the **DICO** code (CAOP `dtmn` == INE
`geocod`), computes centroids with shapely, and writes the simulator standard format:

1. `municipalities.csv` — `id,name,population,lat,lon`; id = DICO, population =
   Censos 2021, centroid from the CAOP polygon. **278 mainland concelhos,
   population 9,855,909** (the exact Censos 2021 mainland figure). The islands cut
   (Madeira/Azores, mirroring Spain's Canary filter) falls out of the CAOP Continente
   join for free.
2. `regions.geojson` — the CAOP polygons re-emitted with feature property `id` = DICO
   (the loader Int-normalizes ids on both sides, so the leading zero in e.g. `0101` is
   harmless). Verified: 278/278 municipalities load with polygons attached.
3. `cities.csv` — 9 mainland cities above 100k population, from GeoNames.

```bash
source data/processing_scripts/.venv/bin/activate   # shapely needed
python3 data/processing_scripts/standardize_portugal.py
```

## Operators (net ids verified against the OpenCellID 268 data)

| Operator | net id | cells |
|---|---|---|
| Vodafone PT | 1 | 7,695 |
| MEO (Altice) | 6 | 6,791 (+4,091 under net 2, MEO's ex-TMN allocation) |
| NOS | 3 | 4,050 |

`main.jl national portugal` uses MEO (net 6) with **18 mainland distritos** as the
edge-UPF count (the Spain-provinces analogue): 6,506 mainland gNBs → 18 edge UPFs → 2
PSAs, all 278 municipalities polygon-matched.

## Iberia scenario (phase 2 — IMPLEMENTED, `main.jl iberia` (runs/iberia.jl))

Two operator fields composed into one topology via `DataLoading.compose_topologies`
(Movistar 52 edge/5 PSA + MEO 18 edge/2 PSA → 52,902 gNBs, 70 edge UPFs, 7 PSAs,
8,322 municipalities; operator tags on gNBs and PSAs). Agents place across both
countries by merged Censos/INE population weights. An agent whose nearest gNB flips
operator has geometrically crossed the border, which **is** the roaming trigger (no
coverage-overlap machinery needed). 5G charges the border per
`RoamingConfig.border_semantics`; 6G-RUPA
renumbers into the visited DIF. Home-Routed path-stretch becomes measurable: serving
PT edge UPF → pinned Spanish PSA.
