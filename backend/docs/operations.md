# Operations

This documents the operational posture of the MedAlert backend: what exists
today, what a real production deployment would still need, and why the split
falls where it does. Written against the proposal's P2 "production hardening"
item, which asked for monitoring, backups, an audit review, and rate
limiting.

## Rate limiting

Already implemented (`medalert_api/settings.py`, `REST_FRAMEWORK` /
`DEFAULT_THROTTLE_RATES`):

| Scope | Rate | Endpoint |
|---|---|---|
| `login` | 20/min | `/api/v1/auth/login/`, `/api/v1/auth/login-identifier/` |
| `register` | 10/min | `/api/v1/auth/register/` |
| `shared_profile` | 30/min | `/api/v1/auth/medical-id/share/<token>/` |
| `pos_sync` | 120/min | `/api/v1/stock/sync/` |

The first three are keyed per-user via DRF's `ScopedRateThrottle`. `pos_sync`
uses a dedicated `POSKeyRateThrottle` (`sync/throttling.py`) keyed on the
`X-POS-API-Key` header instead, since `request.user` on that endpoint is a
`Pharmacy` instance, not a Django `User` -- the default throttle assumes
`.is_authenticated` and crashes on it.

Every other endpoint (pharmacy search, blood bank/ambulance lookup, medicine
availability) is intentionally unthrottled: they're read-only, public, and
rate-limiting them would only get in the way of normal use during a demo on
shared wifi.

## Logging (application-level monitoring)

Already implemented (`medalert_api/settings.py`, `LOGGING`). Every unhandled
exception (`django.request`, level `ERROR`) and every rejected auth attempt
or disallowed-host hit (`django.security`, level `WARNING`) is written to
both the console and a rotating file at `backend/logs/django.log` (5 MB per
file, 5 backups kept). `logs/` is already git-ignored.

This is the half of "monitoring" that's genuinely achievable inside the
Django app itself. It is **not** a substitute for:

- **Uptime monitoring** -- an external service (UptimeRobot, a hosting
  platform's built-in health check, etc.) polling `GET /api/v1/health/` on
  an interval and alerting on failure. The endpoint exists
  (`medalert_api/views.py`); wiring a monitor up to it is a deployment-time
  step that depends on where the app actually gets hosted, so it isn't
  something the codebase can do on its own.
- **Error tracking** (Sentry or similar) -- would need its own account and
  DSN; reasonable next step once there's a real deployment target.

## Health check

`GET /api/v1/health/` -- unauthenticated. Runs `SELECT 1` against the
database and returns:

- `200 {"status": "ok", "database": "ok"}` when the DB answers
- `503 {"status": "error", "database": "unreachable"}` when it doesn't

Deliberately does not check the Channels/Redis layer -- the default
`InMemoryChannelLayer` has nothing external to check, and this endpoint
should stay meaningful without edits if a deployment switches to the Redis
layer later.

## Backup and recovery

Not automated -- there's no scheduler or managed backup service in this
project's scope -- but here is the tested manual procedure, run against a
local PostgreSQL instance with the same `DATABASE_*` values as `.env`:

**Backup:**
```bash
pg_dump -U $DATABASE_USER -h $DATABASE_HOST -p $DATABASE_PORT $DATABASE_NAME > medalert_backup_$(date +%Y%m%d).sql
```

**Restore (into a fresh, empty database):**
```bash
createdb -U $DATABASE_USER -h $DATABASE_HOST -p $DATABASE_PORT medalert_restore_test
psql -U $DATABASE_USER -h $DATABASE_HOST -p $DATABASE_PORT medalert_restore_test < medalert_backup_20260817.sql
```

**Verify the restore actually worked** rather than trusting a clean exit
code -- run these against the restored database and compare against the
source:
```sql
SELECT COUNT(*) FROM pharmacy_pharmacy;
SELECT COUNT(*) FROM sync_stocktransaction;
```
`sync_stocktransaction`'s row count is the more important of the two to
check: it's the append-only audit ledger the non-functional requirements
call out specifically (§3.1.2, Data Integrity), so a restore that silently
drops or truncates it would be the single worst failure mode for this
table.

For an actual production deployment, this manual procedure should become a
scheduled job (cron, or the hosting platform's managed backup feature if
using Railway/Render's managed Postgres) with off-site storage for the dump
files -- backing up to the same disk as the database defeats the purpose if
that disk is what fails.

## Audit review

The append-only `StockTransaction` ledger (`sync/models.py`) already *is*
the audit trail for stock changes -- every write, `changed_by`, `source`
(`POS_SYNC` vs `MANUAL`), and timestamp is preserved and never mutated
(enforced at the application level; see the model's docstring). What's
still manual is periodically reviewing it: no scheduled job currently flags
anomalies (a sudden run of large negative deltas, a spike from one
`POSIntegrationKey`, etc.). For the scope of this project, `OwnerTransactionViewSet`
(`GET /api/v1/my-pharmacy/transactions/`) is the reviewable surface --
a pharmacy owner can already see their own ledger; there's no equivalent
cross-pharmacy admin view yet, which would be the natural next step if this
became a real deployment.