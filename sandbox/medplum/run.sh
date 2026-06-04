#!/usr/bin/env bash
set -euo pipefail

# Medplum Sandbox Entrypoint
# Modes: build, test, start, validate

source /lib/output.sh

MODE="${1:-build}"
WORKSPACE="/workspace"
cd "$WORKSPACE"

case "$MODE" in
  build)
    echo "=== Medplum: Build ==="
    capture_run "build" turbo run build --filter=@medplum/server...
    emit_summary $?
    ;;

  test)
    echo "=== Medplum: Test ==="
    
    # Patch config hosts for Docker network (medplum.config.json uses localhost by default)
    if [ -n "${MEDPLUM_REDIS_HOST:-}" ]; then
      node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync('packages/server/medplum.config.json','utf8'));
        cfg.redis.host = process.env.MEDPLUM_REDIS_HOST || 'localhost';
        cfg.database.host = process.env.POSTGRES_HOST || 'localhost';
        fs.writeFileSync('packages/server/medplum.config.json', JSON.stringify(cfg, null, 2));
      "
    fi

    # Run database seed first (creates schema + seed data)
    echo "Seeding test database..."
    cd packages/server
    capture_run "seed" npx jest seed.test.ts --testTimeout=400000 --forceExit
    if [ $? -ne 0 ]; then
      emit_summary 1
      exit 1
    fi

    # Run the test suite
    echo "Running test suite..."
    capture_run "test" npx jest --forceExit --testTimeout=30000
    cd "$WORKSPACE"
    emit_summary $?
    ;;

  start)
    echo "=== Medplum: Start ==="
    
    # Patch config hosts for Docker network
    if [ -n "${MEDPLUM_REDIS_HOST:-}" ]; then
      node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync('packages/server/medplum.config.json','utf8'));
        cfg.redis.host = process.env.MEDPLUM_REDIS_HOST || 'localhost';
        cfg.database.host = process.env.POSTGRES_HOST || 'localhost';
        fs.writeFileSync('packages/server/medplum.config.json', JSON.stringify(cfg, null, 2));
      "
    fi

    # Start server (auto-migrates via MEDPLUM_DATABASE_RUN_MIGRATIONS=true env var)
    echo "Starting Medplum server..."
    cd packages/server
    node --import ./dist/otel/instrumentation.js dist/index.js env &
    SERVER_PID=$!
    cd "$WORKSPACE"

    # Wait for health check
    wait_for_http "http://localhost:8103/healthcheck" 120
    ret=$?

    if [ $ret -eq 0 ]; then
      # Capture health check response
      curl -s http://localhost:8103/healthcheck > /output/healthcheck_response.json 2>/dev/null || true
      echo "[PASS] Medplum server is running and healthy"
      cat /output/healthcheck_response.json 2>/dev/null || true
      echo "Keeping server alive... (Ctrl+C to stop)"
      wait $SERVER_PID
    else
      echo "[FAIL] Medplum server failed to start"
      kill $SERVER_PID 2>/dev/null || true
    fi
    exit $ret
    ;;

  validate)
    echo "=== Medplum: Full Validation ==="
    
    # Step 1: Build
    capture_run "build" turbo run build --filter=@medplum/server...
    if [ $? -ne 0 ]; then
      emit_summary 1
      exit 1
    fi

    # Step 2: Seed + Test
    echo "Seeding test database..."
    # Patch config hosts for Docker network
    if [ -n "${MEDPLUM_REDIS_HOST:-}" ]; then
      node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync('packages/server/medplum.config.json','utf8'));
        cfg.redis.host = process.env.MEDPLUM_REDIS_HOST || 'localhost';
        cfg.database.host = process.env.POSTGRES_HOST || 'localhost';
        fs.writeFileSync('packages/server/medplum.config.json', JSON.stringify(cfg, null, 2));
      "
    fi
    cd packages/server
    capture_run "seed" npx jest seed.test.ts --testTimeout=400000 --forceExit
    if [ $? -ne 0 ]; then
      cd "$WORKSPACE"
      emit_summary 1
      exit 1
    fi

    echo "Running tests..."
    capture_run "test" npx jest --forceExit --testTimeout=30000
    cd "$WORKSPACE"
    local_exit=$?
    if [ $local_exit -ne 0 ]; then
      emit_summary $local_exit
      exit $local_exit
    fi

    # Step 3: Start server and health check (server auto-migrates via MEDPLUM_DATABASE_RUN_MIGRATIONS=true)
    echo "Starting server for runtime validation..."
    cd packages/server
    node --import ./dist/otel/instrumentation.js dist/index.js env &
    SERVER_PID=$!
    cd "$WORKSPACE"

    wait_for_http "http://localhost:8103/healthcheck" 120
    ret=$?

    if [ $ret -eq 0 ]; then
      curl -s http://localhost:8103/healthcheck > /output/healthcheck_response.json
      echo "[PASS] Full validation successful"
      cat /output/healthcheck_response.json
    else
      echo "[FAIL] Runtime validation failed"
    fi

    kill $SERVER_PID 2>/dev/null || true
    emit_summary $ret
    exit $ret
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: run.sh [build|test|start|validate]"
    exit 1
    ;;
esac
