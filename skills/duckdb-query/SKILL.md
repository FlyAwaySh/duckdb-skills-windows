---
name: duckdb-query
description: >
  Run SQL queries against the attached DuckDB database or ad-hoc against files.
  Accepts raw SQL or natural language questions. Uses DuckDB Friendly SQL idioms.
argument-hint: <SQL or question> [--file path]
allowed-tools: Bash
---

You are helping the user query data using DuckDB.

Input: `$@`

Follow these steps in order.

## Execution rules (all platforms)

- All DuckDB work runs through the Python package via a quoted heredoc; no CLI is used:

```bash
python - <<'PY'
import duckdb, csv, sys
con = duckdb.connect(':memory:')
cur = con.execute("""
<SQL>
""", [<PARAMS>])
w = csv.writer(sys.stdout)
w.writerow([d[0] for d in cur.description])
w.writerows(cur.fetchall())
PY
```

- Local file paths pass as `?` parameters with raw-string literals: `[r'D:\data\file.csv']`. Forward slashes equally fine: `r'D:/data/file.csv'`. Never splice a path into SQL text.
- Multi-statement setup (LOAD, SECRET, SET) runs as separate `con.execute(...)` calls before the query.
- Output CSV to stdout.

## Step 1 — Resolve state and determine the mode

Look for an existing state file in either location:

```bash
python - <<'PY'
from pathlib import Path
import re
proj = Path.cwd() / '.duckdb-skills' / 'state.sql'
safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', '-', str(Path.cwd()))
home = Path.home() / '.duckdb-skills' / safe / 'state.sql'
print(proj if proj.exists() else (home if home.exists() else ''))
PY
```

If a state file was found, replay it and verify the databases it references are accessible:

```bash
python - <<'PY'
import duckdb
from pathlib import Path
state = Path(r'<STATE_FILE>')
con = duckdb.connect(':memory:')
for stmt in filter(str.strip, state.read_text(encoding='utf-8').split(';')):
    con.execute(stmt)
print(con.execute('SHOW DATABASES;').fetchall())
PY
```

If any ATTACH in it fails, warn the user and fall back to ad-hoc mode.

Now determine the mode:

- **Ad-hoc mode** if: the `--file` flag is present, or the SQL references file paths/literals (e.g. `FROM 'data.csv'`), or no state file exists.
- **Session mode** if: a state file exists and the input references table names, is natural language, or is SQL without file references.

If no state file exists and no file is referenced, fall back to ad-hoc mode against `:memory:` — the user must reference files directly in their SQL.

## Step 2 — Check the Python package

```bash
python -c "import duckdb"
```

If not found, tell the user to run `python -m pip install duckdb`, then continue.

## Step 3 — Generate SQL if needed

If the input is natural language (not valid SQL), generate SQL using the Friendly SQL reference below.

In **session mode**, first retrieve the schema to inform query generation:

```bash
python - <<'PY'
import duckdb, csv, sys
from pathlib import Path
state = Path(r'<STATE_FILE>')
con = duckdb.connect(':memory:')
for stmt in filter(str.strip, state.read_text(encoding='utf-8').split(';')):
    con.execute(stmt)
for table, in con.execute("SELECT table_name FROM duckdb_tables() ORDER BY table_name;").fetchall():
    print('TABLE', table)
    print(con.execute(f'DESCRIBE {table};').fetchall())
PY
```

Use the schema context and the Friendly SQL reference to generate the most appropriate query.

## Step 4 — Estimate result size

Before executing, estimate whether the query could produce a very large result that would
consume excessive tokens when returned to this conversation.

**Session mode** — check row counts for the tables involved:

```python
con.execute("SELECT table_name, estimated_size, column_count FROM duckdb_tables() WHERE table_name IN ('<t1>', '<t2>');")
```

**Ad-hoc mode** — probe the source (sandboxed; `allowed_paths` entries must be exact file paths, not directories):

```bash
python - <<'PY'
import duckdb
p = r'<FILE_PATH>'
con = duckdb.connect(':memory:')
con.execute("SET allowed_paths=['" + p.replace("'", "''") + "']")
con.execute('SET enable_external_access=false')
con.execute('SET lock_configuration=true')
print(con.execute('SELECT count() FROM read_csv(?)', [p]).fetchone())
PY
```

**Evaluate**:
- If the query already has a `LIMIT`, `count()`, or other aggregation that bounds the output → safe, proceed.
- If the source has **>1M rows** and the query has no LIMIT or aggregation → tell the user:
  *"This query would return a very large result set. Displaying it here would consume a lot of tokens and increase cost. I'd recommend adding `LIMIT 1000` or an aggregation to keep the output manageable."*
  Ask for confirmation before running as-is.
- If the data size is **>10 GB** → additionally warn:
  *"This table is over 10 GB — the query may take a while to complete."*
  Proceed if the user confirms.

Skip this step for queries that are intrinsically bounded (e.g. `DESCRIBE`, `SUMMARIZE`, aggregations, `count()`).

## Step 5 — Execute the query

**Ad-hoc mode** (sandboxed — only the referenced files are accessible):

```bash
python - <<'PY'
import duckdb, csv, sys
p1 = r'<FILE_PATH_1>'
p2 = r'<FILE_PATH_2>'
con = duckdb.connect(':memory:')
paths = ','.join("'" + p.replace("'", "''") + "'" for p in [p1, p2])
con.execute('SET allowed_paths=[' + paths + ']')
con.execute('SET enable_external_access=false')
con.execute('SET allow_persistent_secrets=false')
con.execute('SET lock_configuration=true')
cur = con.execute("""
<QUERY referencing the files>
""", [p1, p2])
w = csv.writer(sys.stdout)
w.writerow([d[0] for d in cur.description])
w.writerows(cur.fetchall())
PY
```

**Session mode** (user-trusted database): replay the state file, then run the query in the same connection.

Report the row count and columns of the result.

## Step 6 — Handle errors

- **Syntax error**: show the error, suggest a corrected query, and re-run.
- **Missing extension** (e.g. `Extension "X" not loaded`): delegate to the duckdb-install skill, then retry.
- **Table not found** (session mode): list available tables with `FROM duckdb_tables()` and suggest corrections.
- **File not found** (ad-hoc mode): locate the file and suggest the corrected path:

```bash
python - <<'PY'
from pathlib import Path
name = '<FILENAME>'
hits = [p for p in Path.cwd().rglob(name) if '.git' not in p.parts][:5]
print(*hits, sep='\n')
PY
```

- **Persistent or unclear DuckDB error**: delegate to the duckdb-docs skill with the error message, apply the fix, retry.

## Step 7 — Present results

Show the query output to the user. If the result has more than 100 rows, note the truncation and suggest adding `LIMIT` to the query.

For natural language questions, also provide a brief interpretation of the results.

---

## DuckDB Friendly SQL Reference

When generating SQL, prefer these idiomatic DuckDB constructs:

### Compact clauses
- **FROM-first**: `FROM table WHERE x > 10` (implicit `SELECT *`)
- **GROUP BY ALL**: auto-groups by all non-aggregate columns
- **ORDER BY ALL**: orders all columns for deterministic results
- **SELECT * EXCLUDE (col1, col2)**: drop columns from wildcard
- **SELECT * REPLACE (expr AS col)**: transform a column in-place
- **UNION ALL BY NAME**: combine tables with different column orders
- **Percentage LIMIT**: `LIMIT 10%` returns a percentage of rows
- **Prefix aliases**: `SELECT x: 42` instead of `SELECT 42 AS x`
- **Trailing commas** allowed in SELECT lists

### Query features
- **count()**: no need for `count(*)`
- **Reusable aliases**: use column aliases in WHERE / GROUP BY / HAVING
- **Lateral column aliases**: `SELECT i+1 AS j, j+2 AS k`
- **COLUMNS(*)**: apply expressions across columns; supports regex, EXCLUDE, REPLACE, lambdas
- **FILTER clause**: `count() FILTER (WHERE x > 10)` for conditional aggregation
- **GROUPING SETS / CUBE / ROLLUP**: advanced multi-level aggregation
- **Top-N per group**: `max(col, 3)` returns top 3 as a list; also `arg_max(arg, val, n)`, `min_by(arg, val, n)`
- **DESCRIBE table_name**: schema summary (column names and types)
- **SUMMARIZE table_name**: instant statistical profile
- **PIVOT / UNPIVOT**: reshape between wide and long formats
- **SET VARIABLE x = expr**: define SQL-level variables, reference with `getvariable('x')`

### Data import
- **Direct file queries**: `FROM 'file.csv'`, `FROM 'data.parquet'`
- **Globbing**: `FROM 'data/part-*.parquet'` reads multiple files
- **Auto-detection**: CSV headers and schemas are inferred automatically

### Expressions and types
- **Dot operator chaining**: `'hello'.upper()` or `col.trim().lower()`
- **List comprehensions**: `[x*2 FOR x IN list_col]`
- **List/string slicing**: `col[1:3]`, negative indexing `col[-1]`
- **STRUCT.* notation**: `SELECT s.* FROM (SELECT {'a': 1, 'b': 2} AS s)`
- **Square bracket lists**: `[1, 2, 3]`
- **format()**: `format('{}->{}', a, b)` for string formatting

### Joins
- **ASOF joins**: approximate matching on ordered values (e.g. timestamps)
- **POSITIONAL joins**: match rows by position, not keys
- **LATERAL joins**: reference prior table expressions in subqueries

### Data modification
- **CREATE OR REPLACE TABLE**: no need for `DROP TABLE IF EXISTS` first
- **CREATE TABLE ... AS SELECT (CTAS)**: create tables from query results
- **INSERT INTO ... BY NAME**: match columns by name, not position
- **INSERT OR IGNORE INTO / INSERT OR REPLACE INTO**: upsert patterns
