---
name: duckdb-convert-file
description: >
  Convert any data file to another format: CSV, Parquet, JSON, Excel, GeoJSON, and more.
  Use when the user says "convert to parquet", "save as xlsx", "export as JSON", "make this a CSV",
  "turn into parquet", or any variation of format-to-format conversion for data files.
  Also triggers when the user wants to write Parquet, Excel, or other binary formats that the agent cannot produce natively.
argument-hint: <input-file> [output-file]
allowed-tools: Bash
---

You are helping the user convert a data file from one format to another using DuckDB.

Input file: `$0`
Output file: `${1:-}`

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package; no CLI is used.
- Input paths pass as `?` parameters with raw strings: `[r'D:\data\in.csv']` (forward slashes equally fine).
- A `COPY ... TO` target has no `?` support: build the statement by doubling any single quote in the target path, then quoting it (see Step 2).

## Step 1 — Resolve input and output

**Input**: `$0`. Treat it as a bare filename when it contains no `/` and no `\`; resolve bare filenames from the working directory:

```bash
python - <<'PY'
from pathlib import Path
name = '<FILENAME>'
hits = [p for p in Path.cwd().rglob(name) if '.git' not in p.parts][:5]
print(*hits, sep='\n')
PY
```

**Output**: If `$1` is provided, use it as the output path. If not, default to the same stem as the input with a `.parquet` extension (e.g., `data.csv` → `data.parquet`).

Infer the output format from the output file extension:

| Extension | Format clause | Requires |
|---|---|---|
| `.parquet`, `.pq` | *(default, no clause needed)* | — |
| `.csv` | `(FORMAT csv, HEADER)` | — |
| `.tsv` | `(FORMAT csv, HEADER, DELIMITER '\t')` | — |
| `.json` | `(FORMAT json, ARRAY true)` | — |
| `.jsonl`, `.ndjson` | `(FORMAT json, ARRAY false)` | — |
| `.xlsx` | `(FORMAT xlsx)` | `INSTALL excel; LOAD excel;` before COPY |
| `.geojson` | `(FORMAT GDAL, DRIVER 'GeoJSON')` | `INSTALL spatial; LOAD spatial;` |
| `.gpkg` | `(FORMAT GDAL, DRIVER 'GPKG')` | `INSTALL spatial; LOAD spatial;` |
| `.shp` | `(FORMAT GDAL, DRIVER 'ESRI Shapefile')` | `INSTALL spatial; LOAD spatial;` |

## Step 2 — Convert

Run a single Python snippet. Prepend extension loads as needed based on both the input and output formats.

For remote inputs (`s3://`, `https://`, etc.), prepend the same protocol setup as the duckdb-read-file skill:

| Protocol | Prepend |
|---|---|
| `s3://` | `INSTALL httpfs; LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER credential_chain);` |
| `gs://` / `gcs://` | `INSTALL httpfs; LOAD httpfs; CREATE SECRET (TYPE GCS, PROVIDER credential_chain);` |
| `https://` / `http://` | `INSTALL httpfs; LOAD httpfs;` |

```bash
python - <<'PY'
import duckdb
from pathlib import Path
inp = Path(r'<INPUT_PATH>')
out = Path(r'<OUTPUT_PATH>')
con = duckdb.connect(':memory:')
# <EXTENSION_LOADS>, one con.execute per statement>
target = "'" + str(out).replace("'", "''") + "'"
rows = con.execute('SELECT count(*) FROM read_csv(?)', [str(inp)]).fetchone()[0]
con.execute(f"""
COPY (FROM read_csv(?)) TO {target} <FORMAT_CLAUSE>;
""", [str(inp)])
print('rows converted:', rows)
print('output size:', out.stat().st_size, 'bytes')
PY
```

Match the source reader to the input format (`read_csv` / `read_parquet` / `read_json_auto` / `read_xlsx` / `st_read` / ...); the snippet above shows `read_csv` for a CSV input.

**If the user mentions partitioning** (e.g., "partition by year"), add `PARTITION_BY (col)` to the format clause. This only works with Parquet and CSV output.

**If the user mentions compression** (e.g., "use zstd"), add `CODEC 'zstd'` for Parquet output.

## Step 3 — Report

On success, report:
- Input file and detected format
- Output file, format, and size in bytes
- Row count if quick to compute

On failure:
- **`ModuleNotFoundError: No module named 'duckdb'`** → tell the user to run `python -m pip install duckdb`
- **Missing extension** → delegate to the duckdb-install skill and retry
- **Input parse error** → suggest the user check the input format or use the duckdb-read-file skill first to inspect it
