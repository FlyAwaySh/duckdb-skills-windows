# duckdb-skills

English | [简体中文](README.zh-CN.md)

DuckDB-powered agent skills for data files, databases, object storage, and documentation search. Works with any agent runtime that loads `SKILL.md` skills — [Claude Code](https://claude.ai/code), ZCode, and compatible CLIs.

Adapted from [duckdb/duckdb-skills](https://github.com/duckdb/duckdb-skills) (MIT). This build runs every DuckDB statement through the [duckdb Python package](https://duckdb.org/docs/api/python/overview) in-process, so the skills behave identically on Windows, macOS, and Linux — no DuckDB CLI and no shell-specific path handling.

## Prerequisites

- Python 3.8+
- The duckdb Python package:

```
python -m pip install duckdb
```

## Installation

### Claude Code (plugin)

Add this repository as a plugin source and install:

```
/plugin marketplace add https://github.com/FlyAwaySh/duckdb-skills
/plugin install duckdb-skills@duckdb-skills
```

Skills are then available as `/duckdb-skills:<skill-name>`.

### Claude Code (local development)

```bash
git clone https://github.com/FlyAwaySh/duckdb-skills.git
cd duckdb-skills
claude --plugin-dir .
```

### ZCode / any SKILL.md runtime (skills directory)

Copy the skill folders you need into your skills directory and they are discovered by name:

```bash
# ZCode user scope (all workspaces)
cp -r skills/* ~/.zcode/skills/

# cross-tool (Claude, Codex, Cursor, ...)
cp -r skills/* ~/.agents/skills/
```

## Skills

### `duckdb-attach-db`
Attach a DuckDB database file for interactive querying. Explores the schema (tables, columns, row counts) and writes a SQL state file so all other skills can restore the session automatically. State lives in the project directory (`.duckdb-skills/state.sql`) or in your home directory (`~/.duckdb-skills/<project>/state.sql`).

```
duckdb-attach-db my_analytics.duckdb
```

Supports multiple databases — running it again appends to the existing state file.

### `duckdb-query`
Run SQL queries against attached databases or ad-hoc against files. Accepts raw SQL or natural language questions. Uses DuckDB's Friendly SQL dialect. Automatically picks up session state from `duckdb-attach-db`.

```
duckdb-query FROM sales LIMIT 10
duckdb-query "what are the top 5 customers by revenue?"
duckdb-query FROM 'exports.csv' WHERE amount > 100
```

### `duckdb-read-file`
Read and explore any data file — CSV, JSON, Parquet, Avro, Excel, spatial, SQLite, Jupyter notebooks, and more — locally or from remote storage (S3, GCS, Azure, HTTPS). Maps the file extension to the right reader function and prints schema, row count, and a sample.

```
duckdb-read-file variants.parquet what columns does it have?
duckdb-read-file s3://my-bucket/data.parquet describe the schema
duckdb-read-file https://example.com/data.csv how many rows?
```

### `duckdb-convert-file`
Convert any data file to another format: CSV, Parquet, JSON, Excel, GeoJSON, GeoPackage, Shapefile, with optional partitioning and compression.

```
duckdb-convert-file data.csv out.parquet
duckdb-convert-file s3://my-bucket/data.parquet local.xlsx
```

### `duckdb-docs`
Search DuckDB and DuckLake documentation and blog posts using full-text search against the hosted search indexes. Queries run over HTTPS by default, with a locally cached index for faster repeat searches.

```
duckdb-docs window functions
duckdb-docs "how do I read a CSV with custom delimiters?"
```

### `duckdb-install`
Install or update DuckDB extensions for the Python package. Supports `name@repo` syntax for community extensions and a `--update` flag that also checks the package version against the latest stable release.

```
duckdb-install spatial httpfs
duckdb-install gcs@community
duckdb-install --update
```

### `duckdb-s3`
Explore and query data on S3, Cloudflare R2, GCS, MinIO, or any S3-compatible storage — list buckets, preview remote files, and query Parquet/CSV/JSON in place without downloading.

```
duckdb-s3 s3://overturemaps-us-west-2/release/2025-08-20/theme=buildings what's there?
```

### `duckdb-spatial`
Answer spatial questions — distances, containment, density, nearest-X — using the spatial extension, with Overture Maps on S3 as a free global data source.

```
duckdb-spatial cafes within 500m of 中央公园
```

### `duckdb-memories`
Search past Claude Code session logs (`~/.claude/projects`) to recover context from previous conversations — decisions, patterns, open TODOs. Only useful when Claude Code session logs exist.

```
duckdb-memories pricing --here
```

## Session state

All skills share a single `state.sql` file per project — a plain SQL file containing ATTACH/USE/LOAD statements, secrets, and macros. When state is first needed, you'll be asked where to store it:

1. **In the project directory** (`.duckdb-skills/state.sql`) — colocated with the project, optionally gitignored
2. **In your home directory** (`~/.duckdb-skills/<project>/state.sql`) — keeps the repo clean

The file is append-only and idempotent. Any skill restores the session by replaying every statement in the file against a fresh in-memory connection. Paths stored in the file are absolute native paths, so the state stays valid across sessions.

## How the skills work together

- `duckdb-read-file` suggests `duckdb-query` for follow-up exploration and `duckdb-attach-db` for persisting large files
- `duckdb-query`, `duckdb-read-file`, and `duckdb-convert-file` use `duckdb-docs` to troubleshoot DuckDB errors
- All skills share the same `state.sql` — secrets and macros set up by one skill are reused by the others, and databases attached by `duckdb-attach-db` are available everywhere

## Platform support

Windows, macOS, and Linux behave identically: every statement runs through the duckdb Python package (`python - <<'PY'` heredocs), file paths pass as SQL parameters in native form (backslash or forward slash both fine, non-ASCII paths included), and no DuckDB CLI or platform-specific shell commands are used.

## Reporting issues & suggestions

Open an issue at this repository. For DuckDB-specific bugs (extension loading, SQL errors), include the package version (`python -c "import duckdb; print(duckdb.__version__)"`) and the full error message.

## License

MIT — see [LICENSE](LICENSE). Derived from [duckdb/duckdb-skills](https://github.com/duckdb/duckdb-skills) by DuckDB Foundation.
