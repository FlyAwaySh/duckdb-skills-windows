---
name: duckdb-install
description: >
  Install or update DuckDB extensions for the Python package. Each argument is either
  a plain extension name (installs from core) or name@repo (e.g. magic@community).
  Pass --update to update extensions instead of installing.
argument-hint: "[--update] [ext1 ext2@repo ext3 ...]"
allowed-tools: Bash
---

Arguments: `$@`

Each extension argument has the form `name` or `name@repo`.
- `name` → `INSTALL name;`
- `name@repo` → `INSTALL name FROM repo;`

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package (`import duckdb`); no CLI is used.
- Extension and repo names go directly into SQL text: accept only `[a-z0-9_]+`, reject anything else.
- Read functions autoload most extensions on demand; this skill serves explicit installs and updates.

## Step 1 — Check the Python package

```bash
python - <<'PY'
import duckdb
print(duckdb.__version__)
PY
```

If this fails, tell the user:

> **The duckdb Python package is not installed.** Install it with:
> - Any OS: `python -m pip install duckdb`
>
> Then re-run this skill.

Stop if the package is unavailable.

## Step 2 — Check for --update flag

If `--update` is present in `$@`, remove it from the argument list and set mode to **update**.
Otherwise mode is **install**.

## Step 3 — Build and run statements

**Install mode:**

```bash
python - <<'PY'
import duckdb
con = duckdb.connect(':memory:')
con.execute('INSTALL httpfs;')
con.execute('INSTALL magic FROM community;')
print('installed')
PY
```

**Update mode:**

First report the package version against the latest stable release:

```bash
python - <<'PY'
import duckdb, urllib.request
latest = urllib.request.urlopen('https://duckdb.org/data/latest_stable_version.txt', timeout=15).read().decode().strip()
print('installed:', duckdb.__version__)
print('latest:   ', latest)
PY
```

- If installed == latest → report the package is up to date.
- If different → ask the user:
  > **duckdb package is outdated** (installed: `CURRENT`, latest: `LATEST`). Upgrade now with `python -m pip install -U duckdb`?

Then update extensions:

- No extension names → update all: `UPDATE EXTENSIONS;`
- With extension names → single call (ignore `@repo`): `UPDATE EXTENSIONS (name1, name2, ...);`

```bash
python - <<'PY'
import duckdb
con = duckdb.connect(':memory:')
con.execute('UPDATE EXTENSIONS;')
print('extensions updated')
PY
```

Report success or failure after the call completes.
