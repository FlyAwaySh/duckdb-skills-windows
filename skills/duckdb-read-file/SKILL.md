---
name: duckdb-read-file
description: >
  Read any data file (CSV, JSON, Parquet, Avro, Excel, spatial, SQLite) or remote URL (S3, HTTPS).
  Use when user references a data file, asks "what's in this file", or wants to preview/profile a dataset.
  Not for source code.
argument-hint: <filename or URL> [question about the data]
allowed-tools: Bash
---

You are helping the user read and analyze a data file using DuckDB.

Filename given: `$0`
Question: `${1:-describe the data}`

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package; no CLI is used.
- Local paths pass as `?` parameters with raw strings: `[r'D:\data\file.csv']` (forward slashes equally fine). Remote URLs pass the same way: `[url]`.
- Output CSV to stdout.

## Step 1 — Resolve the path

`RESOLVED_PATH` is `$0`. Treat it as a bare filename when it contains no `/` and no `\`.
Resolve bare filenames from the working directory:

```bash
python - <<'PY'
from pathlib import Path
name = '<FILENAME>'
hits = [p for p in Path.cwd().rglob(name) if '.git' not in p.parts][:5]
print(*hits, sep='\n')
PY
```

For local files keep the resolved absolute path in native form (backslashes on Windows are fine).

## Step 2 — Read it

Pick the reader by file extension, then run a single Python snippet against it:

| Extensions | Reader function |
|---|---|
| `.json` `.jsonl` `.ndjson` `.geojson` `.geojsonl` `.har` | `read_json_auto` |
| `.csv` `.tsv` `.tab` `.txt` | `read_csv` |
| `.parquet` `.pq` | `read_parquet` |
| `.avro` | `read_avro` |
| `.xlsx` `.xls` | `read_xlsx` |
| `.shp` `.gpkg` `.fgb` `.kml` | `st_read` |
| `.db` `.sqlite` `.sqlite3` | `sqlite_scan` (list tables with `sqlite_master` first) |
| `.ipynb` | `read_json_auto` + cell unnest (special case below) |
| anything else | `read_blob` |

For **remote files**, prepend the necessary LOAD/SECRET before the reader:

| Protocol | Prepend |
|---|---|
| `https://` / `http://` | `INSTALL httpfs; LOAD httpfs;` |
| `s3://` | `INSTALL httpfs; LOAD httpfs; CREATE SECRET (TYPE S3, PROVIDER credential_chain);` |
| `gs://` / `gcs://` | `INSTALL httpfs; LOAD httpfs; CREATE SECRET (TYPE GCS, PROVIDER credential_chain);` |
| `az://` / `azure://` / `abfss://` | `INSTALL httpfs; LOAD httpfs; INSTALL azure; LOAD azure; CREATE SECRET (TYPE AZURE, PROVIDER credential_chain);` |

For **local files**, no prefix needed.

```bash
python - <<'PY'
import duckdb, csv, sys
p = r'<RESOLVED_PATH_OR_URL>'
fn = '<READER>'   # from the table above
con = duckdb.connect(':memory:')
# <REMOTE_PREFIX>, one con.execute per statement>

def dump(title, cur):
    print('##', title)
    w = csv.writer(sys.stdout)
    w.writerow([d[0] for d in cur.description])
    w.writerows(cur.fetchall())
    print()

dump('schema', con.execute(f'DESCRIBE FROM {fn}(?)', [p]))
dump('row count', con.execute(f'SELECT count(*) FROM {fn}(?)', [p]))
dump('sample', con.execute(f'FROM {fn}(?) LIMIT 20', [p]))
PY
```

**SQLite special case** — list tables first, then read the first one (or ask the user which):

```python
table = con.execute('SELECT name FROM sqlite_master(?) LIMIT 1', [p]).fetchone()[0]
dump('tables', con.execute('SELECT name FROM sqlite_master(?)', [p]))
dump('sample', con.execute('SELECT * FROM sqlite_scan(?, ?) LIMIT 20', [p, table]))
```

**Notebook special case** — read cells as rows:

```python
dump('cells', con.execute("""
    SELECT cell_idx, cell.cell_type,
           array_to_string(cell.source, '') AS source,
           cell.execution_count
    FROM read_json_auto(?), UNNEST(cells) WITH ORDINALITY AS t(cell, cell_idx)
    ORDER BY cell_idx LIMIT 20
""", [p]))
```

**If this fails:**
- **`ModuleNotFoundError: No module named 'duckdb'`** → tell the user to run `python -m pip install duckdb`, then retry.
- **Missing extension** (e.g. spatial files, xlsx, sqlite) → retry with `INSTALL spatial; LOAD spatial;` or `INSTALL sqlite_scanner; LOAD sqlite_scanner;` prepended before the reader (see the duckdb-install skill).
- **Parse error with the auto-detected reader** → inspect the first bytes (`print(open(p, 'rb').read(200))` for local files) and switch to explicit options (e.g. `read_csv(?, delim=';', header=false)`) or a different reader.

## Step 3 — Answer

Using the schema, row count, and sample rows, answer:

`${1:-describe the data: summarize column types, row count, and any notable patterns.}`
