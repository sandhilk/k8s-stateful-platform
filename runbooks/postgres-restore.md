# Runbook: Postgres backup stale / restore from backup

**Alerts:** `PostgresBackupStale`, `PostgresReplicationLagHigh`
**Owner:** platform on-call · **Severity:** high (data-loss risk grows with every hour)

## 1. Triage (5 min)
```bash
kubectl -n data get cluster pg-main            # phase, ready instances, primary
kubectl -n data get backups --sort-by=.metadata.creationTimestamp | tail -5
kubectl cnpg status pg-main -n data            # if the cnpg kubectl plugin is installed
```
- Is the object store reachable? `kubectl -n data get pods -l app=s3`
- Is WAL archiving failing? look for `ContinuousArchiving` condition = False in `kubectl -n data describe cluster pg-main`

## 2. Backup stale — fix
1. Check credentials secret `s3-creds` and bucket `pg-backups` exist.
2. Trigger an on-demand backup and watch it:
   `kubectl -n data apply -f - <<< '{"apiVersion":"postgresql.cnpg.io/v1","kind":"Backup","metadata":{"name":"manual-'$(date +%s)'"},"spec":{"cluster":{"name":"pg-main"}}}'`
3. Alert clears when `cnpg_collector_last_available_backup_timestamp` updates.

## 3. Replication lag — fix
- Check node pressure (`kubectl top nodes`), long-running queries on primary (`pg_stat_activity`), and replica pod restarts.
- If one replica is broken beyond repair: delete its PVC + pod; CNPG re-clones it from the primary.

## 4. Full restore (data corruption / accidental delete)
1. **Declare incident.** Stop writers (scale app to 0) so you know the recovery point.
2. Restore to a NEW cluster — never overwrite the broken one until verified:
   `kubectl apply -f manifests/postgres/restore-drill.yaml` (add `recoveryTarget.targetTime` for PITR).
3. Verify row counts / marker data, then repoint the app Service/secret to the new cluster.
4. Keep the old cluster for forensics for 24h, then delete.

## Verify
`./scripts/pg-restore-drill.sh` — run monthly; record the RTO in the table below.

| Date | RTO measured | Who |
|------|--------------|-----|
