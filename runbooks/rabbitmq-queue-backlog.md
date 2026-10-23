# Runbook: RabbitMQ queue backlog / memory alarm

**Alerts:** `RabbitMQQueueBacklog`, `RabbitMQMemoryAlarm`
**Severity:** high — a memory alarm **blocks all publishers** cluster-wide.

## 1. Triage
```bash
kubectl -n messaging exec mq-server-0 -- rabbitmqctl list_queues name type messages_ready messages_unacknowledged consumers
kubectl -n messaging exec mq-server-0 -- rabbitmq-diagnostics alarms
kubectl -n messaging exec mq-server-0 -- rabbitmq-diagnostics memory_breakdown
```
Questions: Are consumers connected (`consumers = 0`)? Is publish rate up or consume rate down? Did a deploy just happen?

## 2. Fix by cause
| Cause | Action |
|-------|--------|
| Consumers down / crash-looping | Fix or roll back the consumer deployment; check its logs |
| Consumers too slow | Scale consumers (HPA on queue depth via KEDA is the long-term fix) |
| Poison message re-queued forever | Move to a dead-letter queue; add `x-delivery-limit` on quorum queues |
| Memory alarm | Scale consumers first; raise memory limit only if genuinely under-provisioned |

## 3. Node lost
Quorum queues survive the loss of 1 of 3 nodes. Check `rabbitmqctl cluster_status`; the operator recreates the pod and it rejoins. If 2 of 3 are down, queues are unavailable (no quorum) — restore nodes, do **not** force-boot unless data loss is accepted.

## Verify
Backlog drains on the Grafana RabbitMQ dashboard; alarm list empty.
