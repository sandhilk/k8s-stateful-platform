#!/usr/bin/env bash
# CI helper: run a command, and on failure surface the last 60 log lines as a
# GitHub annotation so failures are readable from the run summary page.
set -o pipefail
"$@" 2>&1 | tee /tmp/ci-step.log
rc=${PIPESTATUS[0]}
if [ "$rc" -ne 0 ]; then
  msg=$(tail -60 /tmp/ci-step.log | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | sed ':a;N;$!ba;s/\n/%0A/g')
  echo "::error title=$* failed (exit $rc)::$msg"
fi
# On success, publish the key results (pass lines, measured RTO / failover time) to the run summary
if [ "$rc" -eq 0 ] && grep -qE 'PASS|RTO|New primary' /tmp/ci-step.log; then
  res=$(grep -E 'PASS|RTO|New primary' /tmp/ci-step.log | sed ':a;N;$!ba;s/\n/%0A/g')
  echo "::notice title=$* results::$res"
fi
exit "$rc"
