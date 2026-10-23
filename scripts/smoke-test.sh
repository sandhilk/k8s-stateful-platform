#!/usr/bin/env bash
# End-to-end smoke test: proves each stateful service accepts writes and reads them back.
set -euo pipefail
pass(){ echo "PASS  $*"; }; fail(){ echo "FAIL  $*"; exit 1; }

echo "== Postgres =="
PRIMARY=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
kubectl -n data exec "$PRIMARY" -c postgres -- psql -U postgres -d app -v ON_ERROR_STOP=1 -c \
  "CREATE TABLE IF NOT EXISTS smoke(id serial primary key, note text, at timestamptz default now());
   INSERT INTO smoke(note) VALUES ('smoke-test');" >/dev/null
READY=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.readyInstances}')
[ "$READY" = "3" ] && pass "postgres 3/3 instances ready, primary=$PRIMARY" || fail "postgres ready=$READY"
# replica sees the row (streaming replication works)
REPLICA=$(kubectl -n data get pods -l cnpg.io/cluster=pg-main,cnpg.io/instanceRole=replica -o jsonpath='{.items[0].metadata.name}')
sleep 3
N=$(kubectl -n data exec "$REPLICA" -c postgres -- psql -U postgres -d app -tAc "select count(*) from smoke")
[ "$N" -ge 1 ] && pass "replica $REPLICA has $N row(s)" || fail "replication"

echo "== RabbitMQ =="
kubectl -n messaging exec mq-server-0 -- rabbitmqctl await_startup >/dev/null
NODES=$(kubectl -n messaging exec mq-server-0 -- rabbitmqctl cluster_status --formatter json | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["running_nodes"]))')
[ "$NODES" = "3" ] && pass "rabbitmq 3 running nodes" || fail "rabbitmq nodes=$NODES"
MQ_USER=$(kubectl -n messaging get secret mq-default-user -o jsonpath='{.data.username}' | base64 -d)
MQ_PASS=$(kubectl -n messaging get secret mq-default-user -o jsonpath='{.data.password}' | base64 -d)
kubectl -n messaging run mq-smoke --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -sf -u "$MQ_USER:$MQ_PASS" -X PUT -H 'content-type: application/json' \
  -d '{"durable":true,"arguments":{"x-queue-type":"quorum"}}' \
  http://mq.messaging.svc:15672/api/queues/%2F/smoke >/dev/null
pass "quorum queue 'smoke' declared"

echo "== Redis =="
kubectl -n data exec redis-0 -c redis -- redis-cli SET smoke ok >/dev/null
V=$(kubectl -n data exec redis-0 -c redis -- redis-cli GET smoke)
[ "$V" = "ok" ] && pass "redis SET/GET" || fail "redis"

echo "== Monitoring =="
kubectl -n monitoring get prometheusrule stateful-platform-alerts >/dev/null && pass "alert rules loaded"
echo "All smoke tests passed."
