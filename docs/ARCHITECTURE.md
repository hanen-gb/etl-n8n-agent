# Technical architecture

## General flow

Two triggers (`When chat message received` / n8n chat, and `Webhook` HTTP) feed the same pipeline:

```
Trigger → session id → agent parent Router (Groq) → text->json → Intent switch → [branch] → Aggregate final response → Respond
```

`session id` normalizes the input (`sessionId`, `chatInput`) regardless of the source. The router agent receives the message and replies with strict JSON `{chatInput, intention, sessionId}`; `text->json` parses that output (falling back to `conversation` if the JSON is malformed). The `Switch` node then routes to one of 8 branches.

## Session state (Postgres)

`etl_sessions` table (see `etl_sessions.sql`):

| Column | Role |
|---|---|
| `session_id` | key, matches the chat session |
| `file_name`, `drive_source_file_id`, `drive_working_file_id`, `spreadsheet_id` | identify the source file and its working copy |
| `status` | `idle` / `ready` / `transforming` / `loaded` |

Every branch that needs the current file starts with a `📥 Lire Session (X)` Postgres node followed by a `🔎 Vérifier session (X)` Code node that builds `sessionStatus: 'ready'|'missing'`, then an `IF` node routes to a friendly error message or the rest of the processing.

**Issue found and fixed during testing**: a `SELECT ... WHERE session_id = $1` query that matches no row returns 0 items in n8n — and a node with 0 input items does not execute any of the following nodes (no error, just silence). All `📥 Lire Session (X)` nodes therefore have `alwaysOutputData: true`, guaranteeing that one (possibly empty) item is always produced, whether the session exists or not.

Similarly, every Postgres node (both reads and tracing writes) has `onError: continueRegularOutput`: a Postgres failure (network issue, database down) must never fail the whole execution and prevent a reply to the user — it degrades gracefully instead (the session is then treated as absent).

## `select_file` branch

```
🔎 Détecter nom de fichier (regex .xlsx|.xls|.csv in the message)
  → IF "A un nom de fichier ?"
      NO  → Search files and folders (lists the source Drive folder) → Code in JavaScript (formats the list)
      YES → extraire nom de fichier
            → extraire seulemnt le fichier excel choisi (Drive search by exact name)
            → 🗂️ Copier vers Working (Drive files.copy with convert:true → Google Sheet, into <WORKING_FOLDER_ID>)
            → extraire spreadsheet id
            → extract sheet ids1 (lists the Sheet's tabs)
            → retourne noms de sheets1 (one item per tab)
            → 📋 Résumer sélection (aggregates into a single summary + verification link)
            → 💾 Upsert Session (INSERT ... ON CONFLICT UPDATE into etl_sessions)
```

## `transform` branch

Chosen approach: **classification + deterministic dispatch**, rather than a live tool-calling LLM agent. Rationale: transformations require chained authenticated HTTP calls (read, compute, write) — a LangChain tool-calling agent would need tools able to make those calls with the Google credential attached, which is more fragile to get right reliably than a simple JSON → Switch → HTTP Request pipeline.

```
📥 Lire Session (Transform) → 🔎 Vérifier session → IF (if absent: error message)
  → 🤖 Agent Parseur Transformation (Groq, strict JSON) → 🧩 Parser action transformation
  → 📑 Lister feuilles (Transform) → 🔎 Résoudre feuille cible (name + sheetGid)
  → 🔀 Type de transformation (Switch on `action`)
```

The parser produces JSON matching this schema:

```json
{
  "action": "clean_text|parse_dates|dedupe|add_calculated_column|format_cells|pivot_table",
  "sheetName": "...",
  "columns": ["..."],
  "case": "upper|lower|proper",
  "targetColumn": "...",
  "formula": "=B{row}*C{row}",
  "numberFormat": "DATE|CURRENCY|PERCENT|NUMBER|TEXT",
  "pivotRows": ["..."],
  "pivotValues": ["..."],
  "pivotAggregation": "SUM|COUNTA|AVERAGE"
}
```

The 6 actions (each: `values.get` read → compute in Code → `values.update` or `batchUpdate` write):

| Action | Sheets API operation |
|---|---|
| `clean_text` | rewrites the target columns to upper/lower/proper case via `values.update` (RAW) |
| `parse_dates` | normalizes date values (regex + `Date` fallback) + `batchUpdate.repeatCell` to set the `DATE` number format |
| `dedupe` | deduplicates by `JSON.stringify(row)`, rewrites the range padding removed rows with blanks |
| `add_calculated_column` | appends a column with a template formula (`{row}` replaced by the row number), written with `USER_ENTERED` so the formula is interpreted |
| `format_cells` | `batchUpdate.repeatCell` with a `numberFormat` (DATE/CURRENCY/PERCENT/NUMBER/TEXT) |
| `pivot_table` | `batchUpdate` with `addSheet` + `updateCells` containing a native `pivotTable` object, in a new `TCD_<timestamp>` tab |

All branches converge to `💾 Update Session (Transform)` then `💾 Trace Transform → BDD`, and the reply always includes the working-copy link for immediate verification.

## `question` / `visualisation` branches

Same principle in both cases: statistics are **computed deterministically in JavaScript** (count, distinct values, sum/average/min/max if the column is mostly numeric, otherwise top values) from the real data read via `values.get`, then injected into the agent's prompt. The LLM only phrases the answer in natural language from these real numbers — it never computes anything itself, which avoids arithmetic mistakes or invented figures.

## `loading` branch

```
📥 Lire Session (Loading) → IF → 📤 Exporter Sheet en XLSX (Drive download + googleFileConversion)
  → 🏷️ Nommer fichier final (FINAL_<name>_<date>.xlsx)
  → 💽 Sauvegarder en Local (readWriteFile, onError continueErrorOutput)
  → ☁️ Copier vers Drive Final (upload to <FINAL_FOLDER_ID>, onError continueErrorOutput)
  → 📎 Charger vers SharePoint (HTTP PUT Microsoft Graph, onError continueErrorOutput)
  → 💾 Update Session (Loaded) → 💾 Trace Loading → BDD → summary reply
```

Every destination has `continueErrorOutput`: a failure on one destination (e.g. SharePoint not configured) doesn't prevent the others from running.

## Bugs found during real testing

1. **Merging the `choix_fichier`/`preparation` intents into `select_file`** requires internal routing (regex + IF), since a single Switch output can't lead to two different node chains depending on whether the user gave a file name or not.
2. **A Postgres failure was killing the entire execution**, including plain conversation which has nothing to do with Postgres — fixed with `onError: continueRegularOutput` on all 14 Postgres nodes.
3. **0 Postgres rows = 0 n8n items = total downstream silence** — fixed with `alwaysOutputData: true` on the 5 session-read nodes.
