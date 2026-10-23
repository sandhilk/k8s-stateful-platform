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
exit "$rc"
