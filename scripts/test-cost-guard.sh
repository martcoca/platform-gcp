#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture_dir="${script_dir}/fixtures/cost-guard"
guard="${script_dir}/cost-guard.sh"

assert_exit() {
  local expected=$1
  local fixture=$2
  local actual

  set +e
  "$guard" "$fixture_dir/$fixture" >/dev/null 2>&1
  actual=$?
  set -e

  if [[ "$actual" -ne "$expected" ]]; then
    printf 'Expected %s for %s, got %s.\n' "$expected" "$fixture" "$actual" >&2
    exit 1
  fi
}

assert_exit 1 denied-plan.json
assert_exit 1 denied-plan.jsonl
assert_exit 0 clean-plan.json
assert_exit 2 errored-plan.jsonl
assert_exit 2 unrecognizable.json
assert_exit 2 empty.json

printf '%s\n' 'cost guard exit contract passed'
