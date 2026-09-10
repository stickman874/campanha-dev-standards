# How to roll back

1. Dokploy → application → Deployments → pick the previous successful build → Redeploy.
2. If a migration was applied: write a compensating migration; never edit or delete the applied one.
3. Record what happened in `docs/dev/handoffs/` and, if a decision follows, in `docs/dev/decisions/`.
