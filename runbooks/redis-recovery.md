# Runbook: Redis down / memory high

**Alerts:** `RedisDown`, `RedisMemoryHigh`

## 1. Triage
```bash
kubectl -n data get pod redis-0 -o wide
kubectl -n data logs redis-0 -c redis --tail=50
kubectl -n data exec redis-0 -c redis -- redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human|evicted'
```

## 2. Redis down
- `CrashLoopBackOff` with AOF errors → corrupted AOF after an unclean stop:
  `kubectl -n data exec redis-0 -c redis -- redis-check-aof --fix /data/appendonlydir/<file>.incr.aof`
- Pending pod → PVC/node problem: `kubectl -n data describe pvc data-redis-0`.
- PDB `maxUnavailable: 0` blocks voluntary eviction (node drains) — drain will wait; coordinate before node maintenance.

## 3. Memory high
- Policy is `allkeys-lru` (cache semantics). Rising `evicted_keys` = cache too small or a key-explosion bug.
- Find big keys: `redis-cli --bigkeys`. Check TTLs are set by the app.

## Limits of this setup (be honest in reviews)
Single instance = no HA. Production would use Redis Sentinel/Cluster or ElastiCache with Multi-AZ.
