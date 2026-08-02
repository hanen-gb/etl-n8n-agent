# Agent d'automatisation de processus ETL — Stage Sofrecom Tunisie

Agent agentique n8n pour le traitement de fichiers Excel : sélection d'un fichier source dans Google Drive, transformations réelles (nettoyage, formats, dates, doublons, colonnes calculées, tableaux croisés dynamiques) via l'API Google Sheets sur une copie de travail, réponses aux questions/statistiques calculées de façon déterministe, et chargement final multi-destination (local, Google Drive, SharePoint).

## Contenu

- `Flowrecom ETL — Excel Agentic v2.json` — workflow n8n principal (à importer dans n8n).
- `Flowrecom ETL — BigQuery Native + MCP Agents (2).json` — version précédente du workflow (conservée pour référence).
- `etl_sessions.sql` — schéma de la table Postgres qui garde l'état de session (fichier courant, copie de travail, spreadsheet actif).

## Prérequis avant import

1. Une instance n8n (auto-hébergée) avec les credentials suivantes configurées : Groq, Google Drive OAuth2, Google Sheets OAuth2, Google OAuth2 (générique), Postgres.
2. Exécuter `etl_sessions.sql` dans la base Postgres utilisée par les nœuds de traçabilité.
3. Créer dans Google Drive : un dossier source pour les fichiers Excel bruts, et deux sous-dossiers `Working` / `Final`. Remplacer les placeholders `<WORKING_FOLDER_ID>` / `<FINAL_FOLDER_ID>` dans le JSON par leurs IDs réels.
4. (Optionnel) Configurer une credential SharePoint pour la destination de chargement correspondante.

## Architecture

Un agent routeur classifie l'intention de chaque message (`select_file`, `transform`, `question`, `visualisation`, `consult`, `loading`, `sharing`, `conversation`) et route vers le sous-flux correspondant. L'état de la session (fichier sélectionné, copie de travail) est conservé dans Postgres entre les messages.
