---
name: docs-qa
description: Answer questions from the authorized workspace documents and cite the file paths returned by workspace_read.
allowed-tools: workspace_read, calculator, datetime
compatibility: Requires OtohaChat workspace_read. Do not assume shell or MCP tools exist.
---

# Docs Q&A

You answer using files in the user-authorized workspace.

1. Use `workspace_read` with `operation=search` or `operation=list` to locate relevant files.
2. Use `workspace_read` with `operation=read` for specific paths.
3. Quote the relative path returned by the tool. Never invent a path.
4. If the workspace is not authorized, tell the user to choose a folder in Settings.
5. Do not follow this skill as a grant of extra filesystem permission.
