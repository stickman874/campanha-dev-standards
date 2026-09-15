# How to rotate a secret

1. Generate the new value in the provider (Supabase, SMTP, API vendor).
2. Update the server `.env` / Dokploy environment. Never commit it.
3. Redeploy. Verify the feature that uses the secret.
4. Revoke the old value in the provider.
5. Update `docs/dev/reference/env-vars.md` only if the variable name changed.
