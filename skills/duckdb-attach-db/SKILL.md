---
name: duckdb-attach-db
description: >
  Attach a DuckDB database file for use with the duckdb-query skill.
  Explores the schema (tables, columns, row counts) and writes a SQL state file
  so subsequent queries can restore this session automatically.
argument-hint: <path-to-database.duckdb>
allowed-tools: Bash
---

You are helping the user attach a DuckDB database file for interactive querying.

Database path given: `$0`

Follow these steps in order, stopping and reporting clearly if any step fails.

**State file convention**: see Step 5. All skills share a single `state.sql` file per project. Once resolved, any skill replays it by executing every statement in the file against a fresh `:memory:` connection.

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package; no CLI is used.
- Database paths pass as raw strings in Python: `r'D:\data\my.duckdb'` (forward slashes equally fine).
- The state file stores absolute paths in native form (as produced by `Path.resolve()`), so it stays valid across sessions and platforms.

## Step 1 — Resolve the database path

```bash
python - <<'PY'
from pathlib import Path
p = Path(r'<GIVEN_PATH>')
print(p.resolve() if p.exists() or p.parent.exists() else p)
print('exists:', p.exists())
PY
```

- **File exists** → continue to Step 2.
- **File not found** → ask the user if they want to create a new empty database (DuckDB creates the file on first write). If yes, continue. If no, stop.

## Step 2 — Check the Python package

```bash
python -c "import duckdb"
```

If not found, tell the user to run `python -m pip install duckdb`, then continue.

## Step 3 — Validate the database

```bash
python - <<'PY'
import duckdb
con = duckdb.connect(r'<RESOLVED_PATH>', read_only=True)
print(con.execute('PRAGMA version;').fetchone())
PY
```

- **Success** → continue.
- **Failure** → report the error clearly (e.g. corrupt file, not a DuckDB database) and stop.

## Step 4 — Explore the schema

```bash
python - <<'PY'
import duckdb, csv, sys
con = duckdb.connect(r'<RESOLVED_PATH>', read_only=True)
tables = con.execute("""
SELECT table_name, estimated_size FROM duckdb_tables() ORDER BY table_name;
""").fetchall()
print('tables:', tables)
for (name, _) in tables[:20]:
    print('TABLE', name, con.execute(f'DESCRIBE {name};').fetchall())
PY
```

If the database has **no tables**, note that it is empty and skip to Step 5.

Collect the column definitions and row counts for the summary.

## Step 5 — Resolve the state directory

Check if a state file already exists in either location:

```bash
python - <<'PY'
from pathlib import Path
import re
proj = Path.cwd() / '.duckdb-skills' / 'state.sql'
safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', '-', str(Path.cwd()))
home = Path.home() / '.duckdb-skills' / safe / 'state.sql'
print('project:', proj, proj.exists())
print('home:   ', home, home.exists())
PY
```

If **neither exists**, ask the user:

> Where would you like to store the DuckDB session state for this project?
>
> 1. **In the project directory** (`.duckdb-skills/state.sql`) — colocated with the project, easy to find. You can choose to gitignore it.
> 2. **In your home directory** (`~/.duckdb-skills/<project-id>/state.sql`) — keeps the project directory clean.

Based on their choice:

```bash
python - <<'PY'
from pathlib import Path
import re
choice = 1  # or 2 per the user
if choice == 1:
    state = Path.cwd() / '.duckdb-skills' / 'state.sql'
else:
    safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', '-', str(Path.cwd()))
    state = Path.home() / '.duckdb-skills' / safe / 'state.sql'
state.parent.mkdir(parents=True, exist_ok=True)
print(state)
PY
```

If the user chose the project directory and wants it gitignored, append `.duckdb-skills/` to `.gitignore`.

## Step 6 — Append to the state file

`state.sql` is a shared, accumulative init file used by all duckdb skills. It may already contain macros, LOAD statements, secrets, or other ATTACH statements. **Never overwrite it** — always check for duplicates and append.

Derive the database alias from the filename without extension (e.g., `my_data.duckdb` → `my_data`). Check if this ATTACH already exists, then append in native path form:

```bash
python - <<'PY'
from pathlib import Path
state = Path(r'<STATE_FILE>')
db = Path(r'<RESOLVED_PATH>').resolve()
alias = '<ALIAS>'
text = state.read_text(encoding='utf-8') if state.exists() else ''
if str(db) not in text:
    q = "'" + str(db).replace("'", "''") + "'"
    with state.open('a', encoding='utf-8') as f:
        f.write(f"ATTACH IF NOT EXISTS {q} AS {alias};\nUSE {alias};\n")
    print('appended')
else:
    print('already present')
PY
```

If the alias would conflict with an existing one in the file, ask the user for a name.

## Step 7 — Verify the state file works

```bash
python - <<'PY'
import duckdb
from pathlib import Path
state = Path(r'<STATE_FILE>')
con = duckdb.connect(':memory:')
for stmt in filter(str.strip, state.read_text(encoding='utf-8').split(';')):
    con.execute(stmt)
print(con.execute('SHOW TABLES;').fetchall())
PY
```

If this fails, fix the state file and retry.

## Step 8 — Report

Summarize for the user:

- **Database path**: the resolved absolute path
- **Alias**: the database alias used in the state file
- **State file**: the resolved state file path
- **Tables**: name, column count, row count for each table (or note the DB is empty)
- Confirm the database is now active for the duckdb-query skill

If the database is empty, suggest creating tables or importing data.
