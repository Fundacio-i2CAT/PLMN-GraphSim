# Canada Data Curation

This document explains how to process and standardize the raw datasets for the Canada
simulation.

## Raw Data Sources

*   **`data/canada/opencellid/302.csv`**: **Cell locations** for MCC 302.
    *   *Source*: [OpenCellID](https://opencellid.org/). 58,979 records, of which
        Telus holds 20,077 (302-220), Rogers 18,303 (302-720), Bell 11,237 (302-610),
        Freedom 4,899 (302-490) and Videotron 2,296 (302-500).
*   **`data/canada/agent-unprocessed-raw-datasets/lcsd000b21a_e.*`**: Census
    subdivision boundaries, 2021 Census cartographic boundary file, projected in
    NAD83 Statistics Canada Lambert (EPSG:3347).
    *   *Source*: [Statistics Canada, 2021 Census boundary files](https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/index-eng.cfm).
*   **`data/canada/agent-unprocessed-raw-datasets/98100002.csv`**: Population and
    dwelling counts by census subdivision.
    *   *Source*: [Statistics Canada, table 98-10-0002](https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=9810000201).

Census subdivisions are Canada's municipal level and play the role that municipios
play in Spain and counties play in the United States.

## Processing Script

### `data/processing_scripts/standardize_canada.py`

1.  **Loads** the population table and keeps census subdivision rows, identified by
    the `A0005` schema marker inside the DGUID.
2.  **Reads** the boundary shapefile with `latin-1` encoding, since the attribute
    table carries accented French place names.
3.  **Reprojects** every polygon from EPSG:3347 to WGS84 and **simplifies** it to a
    200 m tolerance.
4.  **Joins** geometry to population on DGUID, which is the only key present in both
    files, and drops subdivisions with no population.
5.  **Outputs** `municipalities.csv` (4,830 subdivisions, 36,991,981 inhabitants,
    matching the published 2021 national count exactly), `regions.geojson` and
    `cities.csv`.

## Official Site Data

Canada does have an official per-site registry, and it is the one to use.

*   **`data/canada/ised/302.csv`**: 43,201 distinct carrier sites, built from the
    **Terrestrial Spectrum Licence Site Data Extract**.
    *   *Source*: [ISED, Download SMS data](https://ised-isde.canada.ca/site/spectrum-management-system/en/download-sms-data),
        file `Site_Data_Extract_FX.zip`, refreshed monthly. Cellular spectrum in Canada
        is licensed by area rather than per transmitter, but licensees must still
        declare the sites operated under those licences, and this extract is the
        result. Per carrier: Telus 14,974, Rogers 12,403 (including Fido),
        Bell Mobility 10,643, Videotron 4,030, SaskTel 1,151.

Do not use `TAFL_LandMobile-LTAF_MobileTerrestre.zip` for this. Despite the name it
covers private land mobile radio and contains almost no carrier cell sites.

### `data/processing_scripts/standardize_canada_ised.py`

One row of the extract is a licence, frequency and site combination, so the 1,772,480
rows collapse to 43,201 sites once deduplicated on rounded coordinates per carrier.
Licensee names are mapped to MNCs, with the two Telus filing names merged and Fido
folded into Rogers, whose network it shares.

## Coverage: Why the Official Field Matters Here

Population living more than 10 km from any recorded site:

| Field | Sites | Population beyond 10 km |
|---|---|---|
| ISED official, all carriers | 43,201 | **4.17 %** |
| OpenCellID, all operators | 58,979 | 14.69 % |
| ISED official, Telus only | 14,974 | 23.57 % |
| OpenCellID, Telus only | 20,077 | 23.76 % |

Two separate effects, worth keeping apart:

*   **Crowdsourcing gap.** At network level the country is well covered, 4.17 % beyond
    10 km, but OpenCellID reports 14.69 %. That difference is missing contributions,
    not missing infrastructure.
*   **Single-operator footprint.** Taking one carrier's declared sites leaves 23 % of
    the population beyond 10 km in both sources, because Bell and Telus share radio
    access and each files only its own sites. A single-operator Canadian field
    therefore understates the coverage a subscriber actually experiences.

Run `canada_ised` when the absolute handover rate has to reflect real sites, and the
all-carrier union when the question is national coverage rather than one operator's.

## Scenario Parameters

| Parameter | Value | Basis |
|---|---|---|
| Edge UPFs | 126 | Census divisions above 50k inhabitants, out of 293 |
| Centralized UPFs | 4 | `round(population / 10M)` clamped to `[2, 5]` |
| Population | 36,991,981 | 2021 Census, summed over the subdivision table |
| Default operator | Telus, 302-220 | Largest field in OpenCellID |

```bash
julia --project main.jl national canada
```
