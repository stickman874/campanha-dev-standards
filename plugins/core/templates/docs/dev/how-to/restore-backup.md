# How to restore a backup

1. Locate the backup (see `../reference/integrations.md` → backups).
2. Restore into a **new** database first; verify row counts and a few known records.
3. Point the app at the restored database (env var) and redeploy.
4. Record the incident in `docs/dev/handoffs/`.
