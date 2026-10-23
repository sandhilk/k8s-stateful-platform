#!/usr/bin/env bash
# Fail fast if any image referenced by the manifests can't be resolved in its registry.
set -uo pipefail
fail=0
for img in $(grep -rhoE '(image|imageName): *[^ ]+' manifests | awk '{print $2}' | sort -u); do
  if docker manifest inspect "$img" >/dev/null 2>&1; then echo "OK      $img"; else echo "MISSING $img"; fail=1; fi
done
exit $fail
