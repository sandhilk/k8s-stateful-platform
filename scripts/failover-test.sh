#!/usr/bin/env bash
# Chaos test: kill the Postgres primary and a RabbitMQ node; measure recovery.
set -euo pipefail
OLD=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
echo "Deleting Postgres primary $OLD"; START=$(date +%s)
kubectl -n data delete pod "$OLD" --wait=false
until NEW=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}') && [ "$NEW" != "$OLD" ] && \
      kubectl -n data exec "$NEW" -c postgres -- pg_isready -q 2>/dev/null; do sleep 1; done
echo "New primary $NEW after $(( $(date +%s) - START ))s"

echo "Deleting RabbitMQ node mq-server-1"
kubectl -n messaging delete pod mq-server-1
# the StatefulSet recreates the pod; wait for it to exist before waiting for Ready
for _ in $(seq 1 60); do kubectl -n messaging get pod mq-server-1 >/dev/null 2>&1 && break; sleep 2; done
kubectl -n messaging wait --for=condition=Ready pod/mq-server-1 --timeout=300s
kubectl -n messaging exec mq-server-0 -- rabbitmqctl list_queues name type messages
echo "Failover test complete."
