# How to deploy

Platform: Dokploy (default) — see Exceptions in AGENTS.md if different.

0. Release only: generate the SBOM and commit it with the tag: `trivy sbom --format cyclonedx --output sbom.json .`
1. Merge to `main`.
2. Dokploy → application → Deploy. Build-time variables (`NEXT_PUBLIC_*`) live in "Build Time Arguments".
3. Verify: open the production URL, check the version in the footer/health endpoint.
4. If it fails: see `rollback.md`.
