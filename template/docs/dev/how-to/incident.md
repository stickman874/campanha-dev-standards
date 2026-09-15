# Incident response

## First hour
1. Contain: revoke credentials, disable the affected feature, or roll back (`rollback.md`).
2. Preserve evidence: export logs before they rotate.
3. Open `docs/dev/handoffs/<date>-incident.md` and log every action with a timestamp.

## Notification clocks (start at discovery)
| Regime | Applies when | Deadline |
|---|---|---|
| GDPR | personal data breach | 72 h to the supervisory authority (Portugal: CNPD); affected people "without undue delay" if high risk |
| NIS2 | only if a client contract requires it | 24 h early warning, 72 h notification, 1 month final report |
| CRA | only if the product is in scope (not plain SaaS) | 24 h early warning, 72 h notification, 14 days final report |

## Afterwards
- Post-mortem in `docs/dev/decisions/` if a decision follows; otherwise `docs/dev/decisions/NNNN-postmortem-<date>.md`.
- Update `docs/dev/explanation/security.md` and `CHANGELOG.md` (Security).
