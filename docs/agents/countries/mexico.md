# Mexico Data Curation

This document explains how to process and standardize the raw datasets for the Mexico
simulation.

## Raw Data Sources

*   **`data/mexico/opencellid/334.csv`**: **Cell locations** for MCC 334.
    *   *Source*: [OpenCellID](https://opencellid.org/). 200,641 records, of which
        Telcel holds 163,116 (334-20), Movistar 14,146 (334-03) and AT&T Mexico
        12,461 (334-50).
*   **`data/mexico/agent-unprocessed-raw-datasets/muni_2018gw.*`**: Municipal
    boundaries, already in WGS84 geographic coordinates.
    *   *Source*: [CONABIO](http://www.conabio.gob.mx/informacion/gis/), which
        republishes the INEGI Marco Geoestadistico. This 40 MB file is used in place
        of the raw INEGI bundle, which ships at 3.4 GB because it also carries
        block-level geometry the simulator does not need.
*   **`data/mexico/agent-unprocessed-raw-datasets/conjunto_de_datos_iter_00CSV20.csv`**:
    Population by locality, Censo 2020 ITER.
    *   *Source*: [INEGI, Censo de Poblacion y Vivienda 2020](https://www.inegi.org.mx/programas/ccpv/2020/).

## Processing Script

### `data/processing_scripts/standardize_mexico.py`

1.  **Reads** the ITER file and keeps municipal totals, which are the rows with
    `LOC == 0000` and a non-zero municipality key. The file is UTF-8 with a byte
    order mark, so it is opened as `utf-8-sig`.
2.  **Reads** the boundary shapefile with `latin-1` encoding for accented names.
3.  **Joins** on CVEGEO, the concatenation of the state and municipality keys, with
    leading zeros stripped so the key survives the loader's id normalization.
4.  **Simplifies** every polygon to a 200 m tolerance and takes a representative
    interior point as the centroid, which is safer than a centroid for the concave
    coastal municipios.
5.  **Outputs** `municipalities.csv` (2,463 municipios, 125,822,502 inhabitants),
    `regions.geojson` and `cities.csv`.

The ITER municipal rows total 126,014,024 nationally, matching the published Censo
2020 figure. The 191,522 difference against the table written here is the population
of municipios that have no polygon in the CONABIO boundary file.

## Official Site Data: What Exists, and Why None of It Is Usable

Mexico is the only country in the set with no official per-site field, and it is not
for lack of looking. Every avenue was checked:

*   **SNII, Sistema Nacional de Informacion de Infraestructura.** Legally this is
    exactly the right registry: the Ley Federal de Telecomunicaciones requires it to
    hold georeferenced active and passive infrastructure for every operator. It was
    launched in June 2024 and initial data upload began in January 2025, but it is
    operated through IFT's Ventanilla Electronica for obligated parties, with no
    public bulk download.
*   **Registro Publico de Concesiones.** Its infrastructure section publishes AM, FM
    and television station data only. Mobile base stations are absent, because
    Mexican mobile spectrum is concessioned by area with no site-level publication
    duty, unlike French declarations above 5 W or Canadian licence site uploads.
*   **Mapa Interactivo de Cobertura 4G.** Built from crowdsourced measurements, so it
    is the same class of evidence as OpenCellID and would not serve as an independent
    check.
*   **Mapas de Cobertura Garantizada Movil.** Operator-declared polygons, and the
    right kind of source, but served only through an interactive application that
    blocks automated access.

The Mexican scenario therefore runs on OpenCellID alone. Its records also rest on a
median of 6 measurement samples, the thinnest evidence of any country here.

## How Far Off Might It Be?

The two countries with both a crowdsourced and an official field give a correction
factor. Population more than 10 km from any recorded site:

| Country | OpenCellID | Official | Ratio |
|---|---|---|---|
| USA | 17.21 % | 5.79 % (FCC ASR) | 3.0 |
| Canada | 14.69 % | 4.17 % (ISED) | 3.5 |
| Mexico | 19.94 % | not available | — |

Both calibrations land near 3, so Mexico's real uncovered population is plausibly
around 7 % rather than the 20 % its OpenCellID field implies. That is an inference,
not a measurement, and the Mexican results should be read accordingly: trustworthy
for the ratio between architectures, which is insensitive to field density, and weak
for absolute handover rates.

## Scenario Parameters

| Parameter | Value | Basis |
|---|---|---|
| Edge UPFs | 445 | Municipios above 50k inhabitants, out of 2,463 |
| Centralized UPFs | 5 | `round(population / 10M)` clamped to `[2, 5]` |
| Population | 125,822,502 | Censo 2020, summed over the municipal table |
| Default operator | Telcel, 334-20 | Largest field in OpenCellID |

```bash
julia --project main.jl national mexico
```
