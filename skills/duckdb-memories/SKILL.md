---
name: duckdb-memories
description: >
  Search past Claude Code session logs to recall prior decisions, patterns, or unresolved work.
  Use when user says "do you remember", "what did we do", references past conversations, or you need context from prior sessions.
  Requires Claude Code session logs under ~/.claude/projects (other agent CLIs do not produce these).
argument-hint: <keyword> [--here]
allowed-tools: Bash
---

Search past session logs silently — do NOT narrate the process. Absorb the results and continue with enriched context.

`$0` is the keyword. Pass `--here` as `$1` to scope to the current project only.

## Execution rules (all platforms)

- DuckDB runs in-process via the Python package; no CLI is used.
- Glob patterns pass as `?` parameters with raw strings.

## Step 1 — Query

```bash
python - <<'PY'
import duckdb, csv, sys
from pathlib import Path
import re
projects = Path.home() / '.claude' / 'projects'
keyword = '<KEYWORD>'
if '<SCOPE>' == 'here':
    safe = re.sub(r'[^A-Za-z0-9]+', '-', str(Path.cwd())).strip('-')
    search = str(projects / safe / '*.jsonl')
else:
    search = str(projects / '*' / '*.jsonl')
con = duckdb.connect(':memory:')
cur = con.execute("""
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  left(message.content::VARCHAR, 500) AS content
FROM read_ndjson(?, auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE ?
  AND message.role IS NOT NULL
ORDER BY timestamp
LIMIT 40;
""", [search, '%' + keyword + '%'])
w = csv.writer(sys.stdout)
w.writerow([d[0] for d in cur.description])
w.writerows(cur.fetchall())
PY
```

Set `SCOPE` to `here` when `--here` was passed, `all` otherwise. If the log directory does not exist, report that no Claude Code session logs were found and stop.

## Step 2 — Internalize

From the results, extract decisions, patterns, unresolved TODOs, and user corrections. Use this to inform your current response — do not repeat raw logs to the user.
