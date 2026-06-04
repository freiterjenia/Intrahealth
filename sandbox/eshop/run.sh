#!/usr/bin/env bash
set -euo pipefail

# eShopOnWeb Sandbox Entrypoint
# Modes: build, test, start, validate

source /lib/output.sh

MODE="${1:-build}"
WORKSPACE="/workspace"
cd "$WORKSPACE"

case "$MODE" in
  build)
    echo "=== eShopOnWeb: Build ==="
    capture_run "build" dotnet build eShopOnWeb.sln -c Release --no-restore
    emit_summary $?
    ;;

  test)
    echo "=== eShopOnWeb: Test ==="
    # Tests use InMemory database — no SQL Server dependency
    capture_run "test" dotnet test eShopOnWeb.sln \
      -c Release \
      --no-restore \
      --logger "trx;LogFileName=results.trx" \
      --results-directory /output/test-results \
      -- RunConfiguration.CollectSourceInformation=true
    emit_summary $?
    ;;

  start)
    echo "=== eShopOnWeb: Start ==="
    # Build first if not already built
    if [ ! -f src/Web/bin/Release/net10.0/Web ]; then
      echo "Building project..."
      dotnet build eShopOnWeb.sln -c Release --no-restore
    fi
    # App auto-migrates and seeds the database on startup
    echo "Starting Web application (will auto-migrate DB)..."
    dotnet run --project src/Web -c Release --no-build --no-launch-profile --urls http://+:8080 &
    APP_PID=$!

    # Wait for app to be ready
    wait_for_http "http://localhost:8080" 120
    ret=$?

    if [ $ret -eq 0 ]; then
      echo "[PASS] eShopOnWeb is running and responding"
      echo "Keeping server alive... (Ctrl+C to stop)"
      wait $APP_PID
    else
      echo "[FAIL] eShopOnWeb failed to start"
      kill $APP_PID 2>/dev/null || true
    fi
    exit $ret
    ;;

  validate)
    echo "=== eShopOnWeb: Full Validation ==="
    
    # Step 1: Build
    capture_run "build" dotnet build eShopOnWeb.sln -c Release --no-restore
    if [ $? -ne 0 ]; then
      emit_summary 1
      exit 1
    fi

    # Step 2: Test (uses InMemory DB, no SQL Server needed)
    capture_run "test" dotnet test eShopOnWeb.sln \
      -c Release \
      --no-build \
      --logger "trx;LogFileName=results.trx" \
      --results-directory /output/test-results
    local_exit=$?
    if [ $local_exit -ne 0 ]; then
      emit_summary $local_exit
      exit $local_exit
    fi

    # Step 3: Start and health check (needs SQL Server)
    echo "Starting app for runtime validation..."
    dotnet run --project src/Web -c Release --no-build --no-launch-profile --urls http://+:8080 &
    APP_PID=$!

    wait_for_http "http://localhost:8080" 120
    ret=$?

    if [ $ret -eq 0 ]; then
      # Capture health check response
      curl -s http://localhost:8080 > /output/healthcheck_response.html
      echo "[PASS] Runtime validation successful"
    else
      echo "[FAIL] Runtime validation failed"
    fi

    kill $APP_PID 2>/dev/null || true
    emit_summary $ret
    exit $ret
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: run.sh [build|test|start|validate]"
    exit 1
    ;;
esac
