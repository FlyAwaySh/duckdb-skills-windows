---
name: duckdb-spatial
description: >
  Answer questions about spatial data using DuckDB. Use when the user mentions locations,
  coordinates, lat/lng, distances, maps, addresses, "near", "within", "closest", geographic
  names, or spatial file formats (GeoJSON, Shapefile, GeoPackage, GPX, GeoParquet). Also
  triggers when the user wants to find places, buildings, or roads — Overture Maps provides
  free global data on S3 with zero API keys. Handles spatial joins, distance calculations,
  containment checks, density analysis, and format conversions for geographic data.
argument-hint: <question or file> [additional context]
allowed-tools: Bash
---

You are answering spatial questions using DuckDB's spatial extension and, when needed, Overture Maps as a free global data source.

Question or file: `$0`
Additional context: `${1:-}`

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package; no CLI is used.
- Local file paths pass as `?` parameters with raw strings: `[r'D:\data\places.geojson']` (forward slashes equally fine). Remote URLs pass the same way.
- Output CSV to stdout.

## Step 1 — Understand what the user needs

Classify the question:

| Pattern | Data source | Key functions |
|---------|-------------|---------------|
| "Find X near Y" (no user file) | Overture Maps on S3 | `ST_Distance_Spheroid`, bbox filtering |
| "How far between A and B" | Geocode or user data | `ST_Distance_Spheroid` |
| "Which points fall inside polygons" | User files | `ST_Contains` |
| "Analyze this GeoJSON/Shapefile/GPX" | User file | `ST_Read`, measurement functions |
| "Show density/hotspots" | User or Overture data | H3 hex binning |
| "Convert to GeoJSON/GeoPackage" | User file | `COPY TO (FORMAT GDAL)` |
| "Count buildings/roads in area" | Overture Maps | bbox filtering + aggregation |

If the question involves real-world places, POIs, buildings, roads, or boundaries and the user hasn't provided a file, use **Overture Maps** — read `references/overture.md` for S3 paths and schema.

For spatial function syntax, read `references/functions.md`.

## Step 2 — Write and run the query

Always start with:
```sql
INSTALL spatial;
LOAD spatial;
SET geometry_always_xy = true;  -- DuckDB 1.5+ only; on 1.4 and earlier this setting does not exist — skip it and follow the coordinate-order rule below
```

Add extensions as needed:
- Overture/remote data: `INSTALL httpfs; LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER config, REGION 'us-west-2');`
- H3 hex binning: `INSTALL h3 FROM community; LOAD h3;`

Run the query in a single Python snippet:

```bash
python - <<'PY'
import duckdb, csv, sys
p = r'<FILE_PATH_OR_URL>'
con = duckdb.connect(':memory:')
con.execute('INSTALL spatial;')
con.execute('LOAD spatial;')
try:
    con.execute('SET geometry_always_xy = true;')  # DuckDB 1.5+; absent on <=1.4
except Exception:
    pass
# <ADDITIONAL_SETUP>, one con.execute per statement>
cur = con.execute("""
<YOUR_QUERY referencing ? for the file>
""", [p])
w = csv.writer(sys.stdout)
w.writerow([d[0] for d in cur.description])
w.writerows(cur.fetchall())
PY
```

### Key principles

**bbox filtering first** — When querying Overture, always filter on `bbox.xmin/xmax/ymin/ymax` before any spatial function. This uses Parquet predicate pushdown and avoids downloading the full dataset.

**Coordinate order is version-dependent** — Spheroid functions (`ST_Distance_Spheroid`, `ST_Area_Spheroid`, ...) interpret `POINT_2D` differently across versions:

- **DuckDB 1.5+**: run `SET geometry_always_xy = true;` once per connection, then construct points as `ST_Point(longitude, latitude)` everywhere.
- **DuckDB 1.4 and earlier**: the setting does not exist and spheroid functions interpret `POINT_2D` as (latitude, longitude) — construct points as `ST_Point(latitude, longitude)` when feeding spheroid functions. Geometry construction and planar functions (`ST_Contains`, `ST_Distance`, ...) keep (longitude, latitude) as usual.

A wrong order produces `nan` or absurd distances (hundreds of thousands of km) — sanity-check one known pair first.

**Use spheroid functions for real-world distances** — `ST_Distance_Spheroid` returns meters on the WGS84 ellipsoid. Plain `ST_Distance` uses planar coordinates and gives meaningless results for lat/lng. **Important:** spheroid functions (`ST_Distance_Spheroid`, `ST_Area_Spheroid`, etc.) require `POINT_2D` inputs, not generic `GEOMETRY`. Overture geometry columns are typed `GEOMETRY('OGC:CRS84')` and cannot be cast directly. Extract coordinates first:
```sql
ST_Point(ST_X(geometry), ST_Y(geometry))::POINT_2D
```

**CSV with lat/lng needs conversion** — build a point column from the two scalar columns, following the coordinate-order rule above for spheroid use. This is the most common gotcha.

## Step 3 — Present results

- For tabular results: show the data directly
- For spatial results: consider exporting to GeoJSON for visualization (`COPY TO 'result.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON')`; the `COPY TO` target is quoted directly — double any single quote in the path)
- For distance/area results: use human-readable units (km for large distances, m for small)
- For density/hotspot results: describe the pattern and offer to export for visualization

If the query fails:
- **`ModuleNotFoundError: No module named 'duckdb'`** → tell the user to run `python -m pip install duckdb`
- **Missing extension** → `INSTALL spatial; LOAD spatial;` or `INSTALL h3 FROM community; LOAD h3;` (see the duckdb-install skill)
- **S3 access denied** → suggest checking AWS credentials
- **No results with Overture** → widen the bbox, check the category spelling, or try a broader search
