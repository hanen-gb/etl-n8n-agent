# Usage examples

These exchanges illustrate the expected behavior for each intent. The `conversation`, `consult`, `question`, `transform` and `visualisation` responses below are real responses captured while testing the workflow (not made-up examples) — useful to check that a new install behaves the same way.

## Call format (webhook)

```bash
curl -X POST http://localhost:5678/webhook/flowrecom-webhook \
  -H "Content-Type: application/json" \
  -d '{"chatInput": "hello", "sessionId": "my_session_1"}'
```

Every response is a JSON object `{text, type, sessionId, charts, key_metrics, summary, timestamp}`.

## 1. Conversation

```json
// Request: {"chatInput":"bonjour, qui es-tu ?","sessionId":"s1"}
{
  "text": "Bonjour ! 😊 Je suis Flowrecom, votre agent conversationnel Sofrecom Tunisie 🤖🇹🇳. Je suis là pour vous aider et répondre à vos questions. Comment puis-je vous aider aujourd'hui ? 🤔",
  "type": "conversation"
}
```

## 2. File selection

Without a specific name (lists the files in the source folder):

```
"chatInput": "list the available files"
→ detected intent: select_file → lists the .xlsx/.xls/.csv files in the source Drive folder
```

With a specific name (starts processing):

```
"chatInput": "bi_dimensions.xlsx"
→ copies the file into Working, converts it to a Google Sheet, detects the tabs,
  saves the session state, returns the working-copy link
```

## 3. Checking the current state

Before a file is selected:

```json
// Request: {"chatInput":"can you check the file's status ?","sessionId":"s1"}
{
  "text": "⚠️ Aucun fichier en cours. Choisissez d'abord un fichier à traiter.",
  "type": "consult"
}
```

Once a file is selected, the response includes the direct working-copy link (`https://docs.google.com/spreadsheets/d/<id>`).

## 4. Questions / statistics

Before a file is selected:

```json
// Request: {"chatInput":"how many rows are in the file ?","sessionId":"s1"}
{
  "text": "⚠️ Aucun fichier sélectionné pour l'instant.",
  "type": "question"
}
```

Once a file is selected, statistics (count, sum, average, distinct values) are computed on the real data and phrased in natural language by the agent — never an invented number.

## 5. Transformation

Examples of recognized requests and the resulting structured action:

| User message | Internal action |
|---|---|
| "uppercase the Name column" | `clean_text`, `case: upper`, `columns: ["Nom"]` |
| "fix the dates in the OrderDate column" | `parse_dates`, `columns: ["DateCommande"]` |
| "remove duplicates" | `dedupe` |
| "add a Total column = Price * Quantity" | `add_calculated_column`, `formula: "=Prix{row}*Quantite{row}"` (actual column names are resolved automatically) |
| "format the Budget column as currency" | `format_cells`, `numberFormat: CURRENCY` |
| "make a pivot table by Channel, sum of Budget" | `pivot_table`, `pivotRows: ["Canal"]`, `pivotValues: ["Budget"]`, `pivotAggregation: SUM` |

Without a selected file:

```json
{
  "text": "⚠️ Aucun fichier sélectionné. Dites-moi d'abord quel fichier vous voulez traiter (ex: 'ouvre bi_dimensions.xlsx').",
  "type": "transform"
}
```

After a successful transformation, the response always includes a verification link, e.g.:

```
🧹 Colonnes ["Nom"] nettoyées.
🔗 Vérifier : https://docs.google.com/spreadsheets/d/<id>
```

## 6. Visualisation

```json
// Request: {"chatInput":"make me a chart","sessionId":"s1"}
{
  "text": "⚠️ Aucun fichier sélectionné pour l'instant.",
  "type": "visualisation"
}
```

With a file selected, the response includes a `charts` array (`type`, `title`, `data.labels`, `data.values`, `insight`) ready to be rendered by the chat frontend.

## 7. Final loading

```json
// Request: {"chatInput":"load the final file","sessionId":"s1"}
{
  "text": "⚠️ Aucun fichier à charger pour l'instant.",
  "type": "loading"
}
```

With a file selected and transformed, the response summarizes the 3 destinations:

```
✅ Chargement terminé !

📄 Fichier : FINAL_bi_dimensions_2026-07-24.xlsx
💽 Local : C:\Users\...\n8n ETL\output\FINAL_bi_dimensions_2026-07-24.xlsx
☁️ Google Drive (Final) : dossier Flowrecom/Final
📎 SharePoint : voir logs d'exécution (nécessite credential configurée)
```

## 8. Sharing

```
"chatInput": "send this report by email to my manager"
→ detected intent: sharing → determines the channel (email) and prepares the message
```
