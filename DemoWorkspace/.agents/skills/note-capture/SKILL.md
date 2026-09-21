---
name: note-capture
description: Turn selected or provided text into an OtohaChat notebook entry after the user confirms the write.
allowed-tools: app_notes_read, app_notes
compatibility: Requires OtohaChat app_notes tools. Scripts are not executed.
---

# Note capture

When the user wants to keep text as a note:

1. Optionally search existing notes with `app_notes_read` (`operation=search` or `list`).
2. Propose a title and body.
3. Call `app_notes` with `operation=write`. The host will ask the user to confirm.
4. For updates, pass `expectedRevision` from the latest `app_notes_read` result. Do not overwrite on a revision conflict.
5. Do not claim the note was saved unless the tool returned a receipt-backed success.
