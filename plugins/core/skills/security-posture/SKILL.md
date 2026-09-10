---
name: security-posture
description: Use when a change touches authentication, permissions, personal data, API handlers, file uploads, payments or external integrations - a judgment checklist that scanners cannot do. Run before codex-review on such diffs.
---

# Security posture review

Scanners (gitleaks, semgrep, trivy) already ran. This is the judgment part. Go through the diff and answer each item with a file:line or "n/a".

## Access
- Every new handler/action checks session first, then permission. Which line?
- Ownership: is any record looked up by a client-supplied id without checking the caller may see it?
- Multi-tenant projects: does every new query hit a tenant-isolated table, or is filtering done only in app code?

## Input and output
- All external input validated by schema? Files: type, size, name sanitised?
- Errors return codes, not stack traces or SQL?
- Anything rendered as HTML from user input?

## Personal data (GDPR)
- New fields that identify a person? Then the inventory in `docs/dev/explanation/security.md` must be updated (purpose, retention, legal basis).
- Any personal data in logs, analytics events, error reports, or emails to third parties?
- Deletion/export paths still work with the new data?

## Secrets and config
- New secret? Named in `.env.example` and `docs/dev/reference/env-vars.md`, value nowhere.
- New third-party call: key server-side only? Timeout and failure behaviour defined?

## Abuse
- Endpoint that sends email, spends money, or enumerates data: rate-limited?
- Background jobs idempotent?

## Output
List findings as `severity — file:line — what — fix`. Fix HIGH items before proceeding. Add a `Security` entry to CHANGELOG [Unreleased] for anything user-relevant. If nothing applies, say "security-posture: nothing applicable" and move on.
