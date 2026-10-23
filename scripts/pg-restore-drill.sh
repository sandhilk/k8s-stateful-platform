#!/usr/bin/env bash
# Backup + restore drill: write a marker row, take an on-demand backup to S3 (MinIO),
# restore into a brand-new cluster, and verify the marker exists. Prints the measured RTO.
set -euo pipefail
NS=data; MARK="drill-$(date +%s)"
PRIMARY=$(kubectl -n $NS get cluster pg-main -o jsonpath='{.status.currentPrimary}')
kubectl -n $NS exec "$PRIMARY" -c postgres -- psql -U postgres -d app -c \
  "CREATE TABLE IF NOT EXISTS drill(m text); INSERT INTO drill VALUES ('$MARK');" >/dev/null
echo "Marker written: $MARK"

kubectl -n $NS exec "$PRIMARY" -c postgres -- psql -U postgres -c "select pg_switch_wal();" >/dev/null
cat <<YAML | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: drill-$(date +%s), namespace: $NS }
spec: { cluster: { name: pg-main } }
YAML
echo "Waiting for backup to complete..."
for i in $(seq 1 60); do
  P=$(kubectl -n $NS get backup -o jsonpath='{.items[-1:].status.phase}')
  [ "$P" = "completed" ] && break; sleep 5
done
[ "$P" = "completed" ] || { echo "backup phase=$P"; exit 1; }

START=$(date +%s)
kubectl -n $NS delete cluster pg-restore-drill --ignore-not-found --wait
kubectl apply -f manifests/postgres/restore-drill.yaml
kubectl -n $NS wait --for=condition=Ready cluster/pg-restore-drill --timeout=600s
RTO=$(( $(date +%s) - START ))

POD=$(kubectl -n $NS get cluster pg-restore-drill -o jsonpath='{.status.currentPrimary}')
FOUND=$(kubectl -n $NS exec "$POD" -c postgres -- psql -U postgres -d app -tAc "select count(*) from drill where m='$MARK'")
[ "$FOUND" = "1" ] && echo "RESTORE OK: marker found. Measured RTO: ${RTO}s" || { echo "RESTORE FAILED"; exit 1; }
kubectl -n $NS delete cluster pg-restore-drill --wait=false
