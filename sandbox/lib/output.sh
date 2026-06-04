#!/usr/bin/env bash
# Shared output capture utilities for the AI Agent Sandbox
# Produces structured JSON results for automated consumption

OUTPUT_DIR="${OUTPUT_DIR:-/output}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR" 2>/dev/null || true

# Capture a command's execution and produce structured JSON output
# Usage: capture_run <label> <command...>
capture_run() {
  local label="$1"
  shift

  local stdout_file="$OUTPUT_DIR/${label}_stdout.log"
  local stderr_file="$OUTPUT_DIR/${label}_stderr.log"
  local result_file="$OUTPUT_DIR/${label}_result.json"

  local start_time
  start_time=$(date +%s)

  # Run command, capture stdout and stderr separately
  "$@" > "$stdout_file" 2> "$stderr_file"
  local exit_code=$?

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Generate structured JSON result
  cat > "$result_file" <<EOF
{
  "label": "$label",
  "command": "$*",
  "exit_code": $exit_code,
  "duration_seconds": $duration,
  "stdout_file": "${label}_stdout.log",
  "stderr_file": "${label}_stderr.log",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  # Also print summary to console
  if [ $exit_code -eq 0 ]; then
    echo "[PASS] $label (${duration}s)"
  else
    echo "[FAIL] $label (exit_code=$exit_code, ${duration}s)"
    # Print last 20 lines of stderr on failure
    echo "--- stderr (last 20 lines) ---"
    tail -20 "$stderr_file"
    echo "---"
  fi

  return $exit_code
}

# Emit a final aggregate result JSON
# Usage: emit_summary <overall_exit_code> <results...>
emit_summary() {
  local overall_exit=$1
  shift
  local summary_file="$OUTPUT_DIR/summary.json"

  # Collect all individual result files
  local results="["
  local first=true
  for f in "$OUTPUT_DIR"/*_result.json; do
    [ -f "$f" ] || continue
    if [ "$first" = true ]; then
      first=false
    else
      results+=","
    fi
    results+=$(cat "$f")
  done
  results+="]"

  cat > "$summary_file" <<EOF
{
  "overall_exit_code": $overall_exit,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "results": $results
}
EOF

  echo ""
  echo "=== Summary written to $summary_file ==="
  echo "Overall: $([ $overall_exit -eq 0 ] && echo 'PASS' || echo 'FAIL')"
}

# Wait for a service to be healthy via HTTP
# Usage: wait_for_http <url> <timeout_seconds> [expected_status]
wait_for_http() {
  local url="$1"
  local timeout="${2:-60}"
  local expected="${3:-200}"
  local elapsed=0

  echo "Waiting for $url (timeout: ${timeout}s)..."
  while [ $elapsed -lt $timeout ]; do
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || true
    if [ "$status" = "$expected" ]; then
      echo "Service ready at $url (${elapsed}s)"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "Timeout waiting for $url after ${timeout}s (last status: $status)"
  return 1
}
