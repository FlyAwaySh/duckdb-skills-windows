# duckdb-skills

[English](README.md) | 简体中文

基于 DuckDB 的智能体技能包，覆盖数据文件读取、格式转换、数据库查询、对象存储浏览与文档检索。任何能加载 `SKILL.md` 技能的智能体运行时都可以使用——[Claude Code](https://claude.ai/code)、ZCode 及其他兼容 CLI。

改编自 [duckdb/duckdb-skills](https://github.com/duckdb/duckdb-skills)（MIT 许可）。本版本的全部 DuckDB 语句通过 [duckdb Python 包](https://duckdb.org/docs/api/python/overview)在进程内执行，Windows、macOS、Linux 行为完全一致——不依赖 DuckDB CLI，不含平台特定的 shell 命令与路径处理。

## 环境要求

- Python 3.8 或更高版本
- duckdb Python 包：

```
python -m pip install duckdb
```

## 安装

### Claude Code（插件方式）

将本仓库添加为插件源并安装：

```
/plugin marketplace add https://github.com/FlyAwaySh/duckdb-skills-windows
/plugin install duckdb-skills@duckdb-skills
```

安装后技能以 `/duckdb-skills:<技能名>` 的形式可用。

### Claude Code（本地开发）

```bash
git clone https://github.com/FlyAwaySh/duckdb-skills-windows.git
cd duckdb-skills-windows
claude --plugin-dir .
```

### ZCode 及其他 SKILL.md 运行时（技能目录）

把需要的技能文件夹复制到技能目录，按名称即可被发现：

```bash
# ZCode 用户级（对所有工作区生效）
cp -r skills/* ~/.zcode/skills/

# 跨工具共享（Claude、Codex、Cursor 等）
cp -r skills/* ~/.agents/skills/
```

## 技能

### `duckdb-attach-db`
挂载 DuckDB 数据库文件用于交互查询。探察表结构（表、列、行数）并写入 SQL 状态文件，供其他技能自动恢复会话。状态可存放在项目目录（`.duckdb-skills/state.sql`）或用户主目录（`~/.duckdb-skills/<project>/state.sql`）。

```
duckdb-attach-db my_analytics.duckdb
```

支持多数据库——重复执行会向现有状态文件追加。

### `duckdb-query`
对已挂载的数据库或文件执行 SQL 查询，接受原生 SQL 或自然语言提问，使用 DuckDB Friendly SQL 方言，自动继承 `duckdb-attach-db` 建立的会话状态。

```
duckdb-query FROM sales LIMIT 10
duckdb-query "what are the top 5 customers by revenue?"
duckdb-query FROM 'exports.csv' WHERE amount > 100
```

### `duckdb-read-file`
读取和探察任意数据文件——CSV、JSON、Parquet、Avro、Excel、空间格式、SQLite、Jupyter notebook 等，支持本地文件与远程地址（S3、GCS、Azure、HTTPS）。按文件扩展名映射到对应的读取函数，输出表结构、行数与样例。

```
duckdb-read-file variants.parquet what columns does it have?
duckdb-read-file s3://my-bucket/data.parquet describe the schema
duckdb-read-file https://example.com/data.csv how many rows?
```

### `duckdb-convert-file`
在任意数据格式之间转换：CSV、Parquet、JSON、Excel、GeoJSON、GeoPackage、Shapefile，支持分区写出与压缩选项。

```
duckdb-convert-file data.csv out.parquet
duckdb-convert-file s3://my-bucket/data.parquet local.xlsx
```

### `duckdb-docs`
对 DuckDB 与 DuckLake 官方文档及博客做全文检索。默认走 HTTPS 直查远端索引，可缓存到本地加速重复检索。

```
duckdb-docs window functions
duckdb-docs "how do I read a CSV with custom delimiters?"
```

### `duckdb-install`
为 Python 包安装或更新 DuckDB 扩展。支持社区扩展的 `name@repo` 语法；`--update` 参数同时检查包版本与最新稳定版的差异。

```
duckdb-install spatial httpfs
duckdb-install gcs@community
duckdb-install --update
```

### `duckdb-s3`
浏览与查询 S3、Cloudflare R2、GCS、MinIO 等对象存储——列举存储桶内容、预览远程文件、对远端 Parquet/CSV/JSON 原地查询而不下载。

```
duckdb-s3 s3://overturemaps-us-west-2/release/2025-08-20/theme=buildings what's there?
```

### `duckdb-spatial`
回答空间问题——距离、包含关系、密度、最近邻——基于 spatial 扩展，并以 S3 上的 Overture Maps 作为免费全球数据源。

```
duckdb-spatial cafes within 500m of 中央公园
```

### `duckdb-memories`
检索 Claude Code 历史会话日志（`~/.claude/projects`），找回过往对话中的决策、模式与未完成事项。仅在存在 Claude Code 会话日志的环境下有意义。

```
duckdb-memories pricing --here
```

## 会话状态

所有技能共享每项目一份 `state.sql`——纯 SQL 文件，包含 ATTACH/USE/LOAD 语句、secret 与宏。首次需要状态时会询问存放位置：

1. **项目目录**（`.duckdb-skills/state.sql`）——与项目同处，可选择加入 gitignore
2. **用户主目录**（`~/.duckdb-skills/<project>/state.sql`）——保持项目目录干净

该文件只追加且幂等。任意技能恢复会话时，把文件中的每条语句在新的内存连接上依次执行。文件中持久化的路径是原生绝对路径，跨会话始终有效。
## 技能协作

- `duckdb-read-file` 会建议用 `duckdb-query` 做后续探察、用 `duckdb-attach-db` 持久化大文件
- `duckdb-query`、`duckdb-read-file`、`duckdb-convert-file` 出错时借助 `duckdb-docs` 检索文档排查
- 所有技能共享同一份 `state.sql`——一个技能配置的 secret 与宏可被其他技能复用，`duckdb-attach-db` 挂载的数据库处处可用

## 平台支持

Windows、macOS、Linux 行为一致：所有语句经 duckdb Python 包执行（`python - <<'PY'` heredoc），文件路径以 SQL 参数的原生形式传递（反斜杠与正斜杠均可，含非 ASCII 路径），不使用 DuckDB CLI，不依赖平台特定的 shell 命令。

## 反馈与建议

在本仓库提 issue 即可。涉及 DuckDB 本身的问题（扩展加载、SQL 报错），请附上包版本（`python -c "import duckdb; print(duckdb.__version__)"`）与完整错误信息。

## 许可证

MIT——见 [LICENSE](LICENSE)。衍生自 DuckDB Foundation 的 [duckdb/duckdb-skills](https://github.com/duckdb/duckdb-skills)。
