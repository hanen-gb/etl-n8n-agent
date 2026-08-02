# Setup guide

## 1. Prerequisites

- Self-hosted n8n (tested on version 2.17.7). The workflow uses generic `httpRequest` nodes to call the Google Sheets/Drive APIs, so no specific community node version is required beyond n8n core + `@n8n/n8n-nodes-langchain`.
- A PostgreSQL database reachable from n8n (local or cloud).
- A Google account with Drive/Sheets enabled, and a Google Cloud project for OAuth2 credentials (or a service account, see below).
- A Groq API key (free) for the LLM agents.

## 2. Database

Run the contents of `etl_sessions.sql` against the Postgres database used by the n8n credential. If an `etl_tracabilite` table doesn't already exist, create it too:

```sql
CREATE TABLE IF NOT EXISTS etl_tracabilite (
  id SERIAL PRIMARY KEY,
  session_id VARCHAR(255),
  agent VARCHAR(100),
  step VARCHAR(100),
  intention VARCHAR(100),
  input_data TEXT,
  output_data TEXT,
  status VARCHAR(50),
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Option: local PostgreSQL instead of a cloud service

If you don't have a cloud PostgreSQL (or the free plan has hit its limit), a local PostgreSQL instance works fine since this database is only used for tracing and session state (no large data volume):

1. Install PostgreSQL (or check it's already running: `sc query postgresql-x64-16` on Windows).
2. `psql -U postgres -c "CREATE DATABASE flowrecom;"`
3. Run the two SQL scripts above against this database.
4. In n8n, create a `postgres`-type credential with `host: localhost`, `port: 5432`, `database: flowrecom`, matching `user`/`password`, `ssl: disable`.

## 3. Google Drive — folder layout

1. Create a Drive folder to hold the **raw** Excel files to process (this is the folder `select_file` lists). Note its ID (from the URL `drive.google.com/drive/folders/<ID>`).
2. Create two subfolders: `Working` (temporary working copies) and `Final` (cleaned files ready to deliver). Note their IDs.
3. In the workflow JSON, replace:
   - `<WORKING_FOLDER_ID>` (node `🗂️ Copier vers Working`)
   - `<FINAL_FOLDER_ID>` (node `☁️ Copier vers Drive Final`)
   - The source folder ID in the `Search files and folders` and `extraire seulemnt le fichier excel choisi` nodes (defaults to an example `Flowrecom` folder).

## 4. Google credentials in n8n

Two possible approaches:

### A. Interactive OAuth2 (quickest to get started)

In n8n → Credentials → New:
- `Google Drive OAuth2 API`
- `Google Sheets OAuth2 API`
- `Google OAuth2 API` (generic, used for the `files.copy` call)

For each, follow n8n's "Sign in with Google" flow. Tokens can expire or be revoked: if a Google node returns an `invalid_grant`/"refresh token invalid" error, reopen the credential and reconnect.

### B. Service account (no expiry, no manual reconnection)

1. [console.cloud.google.com](https://console.cloud.google.com) → select or create a project.
2. **APIs & Services → Library** → enable **Google Drive API** and **Google Sheets API**.
3. **IAM & Admin → Service Accounts → Create Service Account** (no project IAM role required).
4. **Keys tab → Add Key → Create new key → JSON** → download.
5. Note the `client_email` field in the JSON (e.g. `name@project.iam.gserviceaccount.com`).
6. In Google Drive, share the source folder (and the `Working`/`Final` subfolders) with that email, **Editor** role.
7. In n8n, create the Drive/Sheets credentials choosing the "Service Account" mode and paste the JSON contents.

## 5. Groq credential

n8n → Credentials → New → `Groq API` → paste the key obtained from [console.groq.com](https://console.groq.com).

## 6. SharePoint (optional — 3rd loading destination)

1. [portal.azure.com](https://portal.azure.com) → **Azure Active Directory → App registrations → New registration**.
2. Once created: **API permissions → Add a permission → Microsoft Graph → Application permissions → Sites.ReadWrite.All** → then **Grant admin consent**.
3. **Certificates & secrets → New client secret** → note the value (shown only once).
4. Gather: Tenant ID, Application (client) ID, Client Secret, and the target SharePoint site ID (`GET https://graph.microsoft.com/v1.0/sites/{hostname}:/{site-path}` to obtain it).
5. In n8n, create a generic OAuth2 credential (client credentials grant) pointing to `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token`, scope `https://graph.microsoft.com/.default`.
6. Replace `<SHAREPOINT_SITE_ID>` in the `📎 Charger vers SharePoint` node and attach the credential.

Until this credential is configured, the branch fails silently (`continueErrorOutput`) without blocking the Local and Drive destinations.

## 7. Import and activation

1. n8n → **Import from File** → select `Flowrecom ETL — Excel Agentic v2.json`.
2. Check/attach credentials on each node if the names don't match exactly.
3. Activate the workflow.
4. Drop a test Excel file into the source Drive folder.
5. Follow the scenarios in [`USAGE.md`](USAGE.md) to validate each intent.

## 8. Local disk writes (`loading` destination)

n8n restricts disk writes to `~/.n8n-files` by default. To allow the output folder configured in the `💽 Sauvegarder en Local` node, set the `N8N_RESTRICT_FILE_ACCESS_TO` environment variable to the allowed path before starting n8n.
