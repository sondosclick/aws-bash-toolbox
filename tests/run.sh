#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.aws"
cat > "$HOME/.aws/config" <<'EOF'
[profile test]
region = us-east-1
output = json
EOF

export ABT_DEFAULT_PROFILE="test"
export ABT_DEFAULT_REGION="us-east-1"
export ABT_COLOR=0
export PS1=""

export PATH="$REPO_ROOT/tests/mocks:$PATH"
export AWS_MOCK_LOG="$TMP_DIR/aws.log"
export FZF_MOCK_STATE="$TMP_DIR/fzf.state"

source "$REPO_ROOT/abt.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  if [ "$expected" != "$actual" ]; then
    fail "expected '$expected' got '$actual'"
  fi
}

run_cmd() {
  RUN_OUT=""
  RUN_STATUS=0
  set +e
  RUN_OUT="$("$@")"
  RUN_STATUS=$?
  set -e
}

run_cmd_input() {
  local input="$1"
  shift
  RUN_OUT=""
  RUN_STATUS=0
  set +e
  RUN_OUT="$(printf "%b" "$input" | "$@")"
  RUN_STATUS=$?
  set -e
}

reset_log() {
  : > "$AWS_MOCK_LOG"
}

reset_fzf() {
  : > "$FZF_MOCK_STATE"
}

echo "Running tests..."

echo "- validate port"
_abt_validate_port 1 || fail "port 1 should be valid"
_abt_validate_port 65535 || fail "port 65535 should be valid"
_abt_validate_port 0 && fail "port 0 should be invalid"
_abt_validate_port 70000 && fail "port 70000 should be invalid"
_abt_validate_port abc && fail "non-numeric port should be invalid"

echo "- select db port (preset)"
reset_fzf
export FZF_MOCK_RESPONSES="postgres (5432)"
run_cmd _abt_select_db_port
assert_eq 0 "$RUN_STATUS"
assert_eq "5432" "$RUN_OUT"

echo "- select db port (custom)"
reset_fzf
export FZF_MOCK_RESPONSES="custom"
run_cmd_input "15432\n" _abt_select_db_port
assert_eq 0 "$RUN_STATUS"
assert_eq "15432" "$RUN_OUT"

echo "- forward default host from tags"
run_cmd _abt_forward_default_host "i-1234567890abcdef0"
assert_eq 0 "$RUN_STATUS"
assert_eq "db.internal" "$RUN_OUT"

echo "- ssm port forward (default local port)"
reset_log
_abt_ssm_port_forward "i-1234567890abcdef0" "db.internal" "5432"
grep -q "AWS-StartPortForwardingSessionToRemoteHost" "$AWS_MOCK_LOG" \
  || fail "missing SSM port forward document"
grep -q "localPortNumber=5432" "$AWS_MOCK_LOG" \
  || fail "missing default local port in parameters"

echo "- ssm port forward (invalid port)"
reset_log
set +e
_abt_ssm_port_forward "i-1234567890abcdef0" "db.internal" "70000"
status=$?
set -e
[ "$status" -ne 0 ] || fail "invalid port should fail"
if [ -s "$AWS_MOCK_LOG" ]; then
  fail "aws should not be called when validation fails"
fi

echo "- abt connect forward routing"
reset_log
abt connect forward "i-1234567890abcdef0" "db.internal" "5432"
grep -q "localPortNumber=5432" "$AWS_MOCK_LOG" \
  || fail "abt connect forward did not use default local port"

echo "- forward select flow"
reset_log
reset_fzf
export FZF_MOCK_RESPONSES=$'i-1234567890abcdef0\tbastion-01\t10.0.0.10\trunning\npostgres (5432)'
printf "\n15432\n" | _abt_forward_select
grep -q "host=db.internal" "$AWS_MOCK_LOG" \
  || fail "forward select did not use suggested host"
grep -q "localPortNumber=15432" "$AWS_MOCK_LOG" \
  || fail "forward select did not use provided local port"

echo "All tests passed."
