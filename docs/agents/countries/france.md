# France Data Curation

This document explains how the French scenario is assembled. France is the only
country in the set with two independent base-station fields: a crowdsourced one
and an official one, which lets the simulator quantify how much a result depends
on the source rather than on the network.

## Raw Data Sources

*   **`data/france/opencellid/208.csv`**: **Cell locations** for MCC 208.
    *   *Source*: [OpenCellID](https://opencellid.org/), crowdsourced. 390,737 records,
        of which the four national operators hold: Orange 116,994 (208-01),
        Bouygues 94,931 (208-20), Free Mobile 87,410 (208-15), SFR 86,758 (208-10).
*   **`data/france/anfr/208.csv`**: **Official site locations**, derived from the ANFR
    BNIR monthly export.
    *   *Source*: [ANFR, Donnees sur les installations radioelectriques de plus de 5 watts](https://www.data.gouv.fr/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1/).
        Every operator is legally required to declare each installation above 5 W, so
        this is the French counterpart of the FCC Antenna Structure Registry used for
        the United States.
*   **Communes with population and boundaries**: fetched at build time from
    [geo.api.gouv.fr](https://geo.api.gouv.fr/), the Etalab service that republishes
    INSEE legal population and IGN commune contours. No manual download is needed.

## Processing Scripts

### `data/processing_scripts/standardize_france.py`

Builds the population layer. It

1.  **Fetches** all communes with their legal population and centroid.
2.  **Excludes** overseas departments (codes starting 97 and 98), keeping metropolitan
    France including Corsica, so that the simulated field is one contiguous landmass.
    This mirrors the mainland cut applied to Portugal.
3.  **Fetches** commune contours department by department and **simplifies** them to a
    200 m tolerance, which is invisible to the rejection sampling used for agent
    placement but keeps the polygon file at 19.5 MB instead of roughly 250 MB.
4.  **Writes** ids with leading zeros stripped, because the loader normalizes any
    integer-looking id through `parse(Int, .)` and would otherwise fail to join
    `"01001"` against `1001`.
5.  **Outputs** `municipalities.csv` (34,746 communes, 66,165,815 inhabitants),
    `regions.geojson` and `cities.csv`.

### `data/processing_scripts/standardize_france_anfr.py`

Builds the official base-station field. It joins `SUP_SUPPORT` (support geometry,
coordinates in degrees, minutes and seconds) to `SUP_STATION` (station to operator),
maps the ANFR operator id to the MNC used by OpenCellID, converts coordinates to
decimal degrees, drops anything outside metropolitan France, and writes the result in
the 14-column OpenCellID layout the loader expects.

Unzip the monthly ANFR export into
`data/france/agent-unprocessed-raw-datasets/anfr/` before running it.

## Cells Are Not Sites

The two fields describe the same network at different granularity, and the difference
is large enough to matter:

| Field | Records for Orange | Median nearest neighbour | Within 50 m |
|---|---|---|---|
| OpenCellID (cells) | 116,994 | 254 m | 14.2 % |
| ANFR (sites) | 33,665 | 2,042 m | 0.8 % |

An OpenCellID record is a cell, so a three-sector site appears roughly three times,
and because each position is independently estimated from crowdsourced measurements,
those sectors land hundreds of metres apart rather than on top of each other. An ANFR
record is a site. The simulator treats every row as one gNB, so the OpenCellID field
produces a denser apparent deployment and a higher handover rate than the physical
network has.

Neither field is wrong; they answer different questions. Run the OpenCellID field for
comparability with the other countries, and the ANFR field when the absolute handover
rate has to correspond to real sites.

## Scenario Parameters

| Parameter | Value | Basis |
|---|---|---|
| Edge UPFs | 96 | Departments, the French second-level administrative unit, all above 50k inhabitants |
| Centralized UPFs | 5 | `round(population / 10M)` clamped to `[2, 5]` |
| Population | 66,165,815 | Sum of the commune table actually loaded |
| Default operator | Orange, 208-01 | Largest field in both sources |

```bash
julia --project main.jl national france
```
