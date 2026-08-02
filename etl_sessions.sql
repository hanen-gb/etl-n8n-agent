-- À exécuter une fois dans la même base Postgres/Supabase que etl_tracabilite.
-- Cette table remplace les hacks "ORDER BY created_at DESC LIMIT 1" par un état
-- explicite : quel fichier / quel Google Sheet de travail est actif pour chaque session de chat.

CREATE TABLE IF NOT EXISTS etl_sessions (
  session_id VARCHAR(255) PRIMARY KEY,
  file_name VARCHAR(255),
  drive_source_file_id VARCHAR(255),
  drive_working_file_id VARCHAR(255),
  spreadsheet_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'idle',
  updated_at TIMESTAMP DEFAULT NOW()
);
