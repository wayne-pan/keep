#!/usr/bin/env bash
# Temporary test script for safety-guard.sh validation
# Usage: bash scripts/test-safety-guard.sh

PASS=0
FAIL=0

assert_deny() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash hooks/safety-guard.sh 2>/dev/null)
  if echo "$result" | grep -q '"deny"'; then
    echo "  PASS (deny): $desc"
    ((PASS++))
  else
    echo "  FAIL (should deny): $desc"
    ((FAIL++))
  fi
}

assert_allow() {
  local desc="$1"
  local cmd="$2"
  local result
  result=$(echo "$cmd" | bash hooks/safety-guard.sh 2>/dev/null)
  if echo "$result" | grep -q '"deny"'; then
    echo "  FAIL (should allow): $desc"
    ((FAIL++))
  else
    echo "  PASS (allow): $desc"
    ((PASS++))
  fi
}

echo "=== OBFUSCATION (should DENY — previously known bypasses, now fixed) ==="
assert_deny "Extra whitespace" '{"tool_input":{"command":"rm   -rf   /"}}'
assert_deny "Backslash escape" '{"tool_input":{"command":"r\\m -rf /"}}'
assert_deny "Tab separation" '{"tool_input":{"command":"rm\t-rf\t/"}}'
assert_deny "eval+base64" '{"tool_input":{"command":"eval $(echo cm0g | base64 -d)"}}'
assert_deny "printf obfuscation" '{"tool_input":{"command":"$(printf rm) -rf /"}}'
assert_deny "Mixed ws+backslash" '{"tool_input":{"command":"r\\m   -rf\t/"}}'
assert_deny "eval with any subst" '{"tool_input":{"command":"eval $(printf %s rm) -rf /"}}'
assert_deny "Command-position echo subst" '{"tool_input":{"command":"$(echo rm) -rf /"}}'
assert_deny "Chained subst after ;" '{"tool_input":{"command":"echo ok ; $(printf rm) -rf /"}}'
assert_deny "awk at cmd position" '{"tool_input":{"command":"$(awk '"'"'{print $1}'"'"' /tmp/x)"}}'
assert_deny "sed at cmd position" '{"tool_input":{"command":"$(sed s/x/y/ /tmp/x)"}}'
assert_deny "dd at cmd position" '{"tool_input":{"command":"$(dd if=/tmp/x)"}}'
assert_deny "tr at cmd position" '{"tool_input":{"command":"$(tr a-z A-Z < /tmp/x)"}}'
assert_deny "head at cmd position" '{"tool_input":{"command":"$(head -1 /tmp/x)"}}'
assert_deny "git at cmd position" '{"tool_input":{"command":"$(git rev-parse HEAD)"}}'
assert_deny "backtick at cmd position" '{"tool_input":{"command":"`rm -rf /`"}}'
assert_deny "exec with subst" '{"tool_input":{"command":"exec $(printf rm) -rf /"}}'
assert_deny "eval with backtick" '{"tool_input":{"command":"eval `echo cm0g | base64 -d`"}}'
assert_deny "exec with backtick" '{"tool_input":{"command":"exec `printf rm` -rf /"}}'

echo ""
echo "=== OBFUSCATION FALSE-POSITIVE GUARD (should ALLOW) ==="
assert_allow "echo \$(date) (subst in args)" '{"tool_input":{"command":"echo $(date)"}}'
assert_allow "echo \$((1+1)) (arithmetic)" '{"tool_input":{"command":"echo $((1+1))"}}'
assert_allow "evaluator (word boundary)" '{"tool_input":{"command":"evaluator --flag x"}}'
assert_allow "x=\$(cat file) (assignment)" '{"tool_input":{"command":"x=$(cat Makefile)"}}'
assert_allow "echo \$(git rev-parse HEAD)" '{"tool_input":{"command":"echo $(git rev-parse HEAD)"}}'
assert_allow "echo \$((2*3)) standalone arithmetic" '{"tool_input":{"command":"echo $((2*3))"}}'
assert_allow "echo \"\$(echo nested)\" (subst in args)" '{"tool_input":{"command":"echo \"$(echo hi)\""}}'
assert_allow "echo \"eval \$(date)\" (eval in quoted str)" '{"tool_input":{"command":"echo \"eval $(date)\""}}'
assert_allow "empty subst \$( )" '{"tool_input":{"command":"$( )"}}'
assert_allow "empty subst \$()" '{"tool_input":{"command":"$()"}}'
assert_allow "find . -name (dot as path arg)" '{"tool_input":{"command":"find . -name x"}}'

echo ""
echo "=== EXISTING BLOCKS (regression — must still DENY) ==="
assert_deny "Direct rm -rf /" '{"tool_input":{"command":"rm -rf /"}}'
assert_deny "Semicolon chain" '{"tool_input":{"command":"cd /tmp ; rm -rf /"}}'
assert_deny "AND chain" '{"tool_input":{"command":"echo ok && rm -rf /"}}'
assert_deny "printenv" '{"tool_input":{"command":"printenv"}}'
assert_deny "cat .env" '{"tool_input":{"command":"cat .env"}}'

echo ""
echo "=== LEGITIMATE COMMANDS (must ALLOW) ==="
assert_allow "git status" '{"tool_input":{"command":"git status"}}'
assert_allow "cd && make" '{"tool_input":{"command":"cd foo && make"}}'
assert_allow "echo with substitution" '{"tool_input":{"command":"echo $(git rev-parse HEAD)"}}'
assert_allow "cat with pipe" '{"tool_input":{"command":"cat file.txt | grep pattern"}}'
assert_allow "npm install" '{"tool_input":{"command":"npm install"}}'
assert_allow "Empty command" '{"tool_input":{"command":""}}'

echo ""
echo "=== FILE BYPASS — DESTRUCTIVE PAYLOAD (should DENY) ==="
# Setup: temp fixtures with destructive + clean content
TMP_SQL=$(mktemp /tmp/sg-test-XXXX.sql)
TMP_SH=$(mktemp /tmp/sg-test-XXXX.sh)
TMP_PY=$(mktemp /tmp/sg-test-XXXX.py)
TMP_DEL=$(mktemp /tmp/sg-test-XXXX.sql)
TMP_CLEAN=$(mktemp /tmp/sg-test-XXXX.sql)
printf 'DROP TABLE users;\n' > "$TMP_SQL"
printf '#!/usr/bin/env bash\nrm -rf /\n' > "$TMP_SH"
printf 'import os\nos.system("aws s3 rb s3://prod --recursive")\n' > "$TMP_PY"
printf 'DELETE FROM sessions;\n' > "$TMP_DEL"
printf 'SELECT 1;\n' > "$TMP_CLEAN"

assert_deny "psql -f <DROP TABLE>" "{\"tool_input\":{\"command\":\"psql -f $TMP_SQL\"}}"
assert_deny "bash <rm -rf />" "{\"tool_input\":{\"command\":\"bash $TMP_SH\"}}"
assert_deny "python <aws s3 rb>" "{\"tool_input\":{\"command\":\"python $TMP_PY\"}}"
assert_deny "psql stdin redirect" "{\"tool_input\":{\"command\":\"psql < $TMP_SQL\"}}"
assert_deny "cat destructive | psql" "{\"tool_input\":{\"command\":\"cat $TMP_SQL | psql\"}}"
assert_deny "psql --file= form" "{\"tool_input\":{\"command\":\"psql --file=$TMP_SQL\"}}"
assert_deny "psql -f <DELETE FROM>" "{\"tool_input\":{\"command\":\"psql -f $TMP_DEL\"}}"
assert_deny "PGPASSWORD ... psql -f" "{\"tool_input\":{\"command\":\"PGPASSWORD=x psql -h localhost -U u -d db -f $TMP_SQL\"}}"
assert_deny "cd /tmp && psql -f" "{\"tool_input\":{\"command\":\"cd /tmp && psql -f $TMP_SQL\"}}"
assert_deny "POSIX dot source destructive" "{\"tool_input\":{\"command\":\". $TMP_SH\"}}"

echo ""
echo "=== FILE BYPASS — CLEAN (should ALLOW) ==="
assert_allow "psql -f clean file" "{\"tool_input\":{\"command\":\"psql -f $TMP_CLEAN\"}}"
assert_allow "psql -f nonexistent" "{\"tool_input\":{\"command\":\"psql -f /tmp/sg-nonexistent-$$.sql\"}}"
assert_allow "PGPASSWORD ... psql -f clean" "{\"tool_input\":{\"command\":\"PGPASSWORD=x psql -h localhost -U u -d db -f $TMP_CLEAN\"}}"
assert_allow "cat clean | grep (no interp)" "{\"tool_input\":{\"command\":\"cat $TMP_CLEAN | grep SELECT\"}}"

echo ""
echo "=== REPO FILE (should ALLOW — not in volatile dir) ==="
# These would have been blocked by the original broad scan. With volatile-dir
# scope, repo files (migrations, deploy scripts, the hook itself, this test)
# are not scanned — eliminates self-DoS and migration false-positives.
assert_allow "bash <repo test script>" "{\"tool_input\":{\"command\":\"bash scripts/test-safety-guard.sh\"}}"
assert_allow "bash -n <hook itself>" "{\"tool_input\":{\"command\":\"bash -n hooks/safety-guard.sh\"}}"
assert_allow "psql -f <repo migration.sql>" "{\"tool_input\":{\"command\":\"psql -f migrations/001_down.sql\"}}"

# Teardown
rm -f "$TMP_SQL" "$TMP_SH" "$TMP_PY" "$TMP_DEL" "$TMP_CLEAN"

echo ""
echo "=== RESULTS ==="
echo "PASS: $PASS  FAIL: $FAIL"
