#!/usr/bin/env bash
set -euo pipefail

# AI Agent Sandbox Orchestrator
# Usage: ./sandbox.sh <project> <command> [options]
#
# Projects: eshop, medplum
# Commands: init, build, test, start, validate, reset, destroy, status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-}"
COMMAND="${2:-}"

usage() {
  cat <<EOF
AI Agent Sandbox — Orchestrator

Usage: ./sandbox.sh <project> <command> [options]

Projects:
  eshop       eShopOnWeb (.NET / SQL Server)
  medplum     Medplum (Node.js / PostgreSQL / Redis)

Commands:
  init        Build container images (uses layer cache)
  build       Run project build inside sandbox
  test        Run test suite inside sandbox
  start       Start application + dependencies
  validate    Full cycle: build → test → start → health check
  reset       Stop containers, wipe source/DB volumes (keep images)
  destroy     Full teardown including images
  status      Show running containers and health

Options:
  --timeout N    Override default timeout (seconds)

Output:
  Structured JSON results are written to ./output/<project>/
EOF
  exit 1
}

# Validate inputs
[ -z "$PROJECT" ] || [ -z "$COMMAND" ] && usage
[[ "$PROJECT" =~ ^(eshop|medplum)$ ]] || { echo "Error: Unknown project '$PROJECT'. Use 'eshop' or 'medplum'."; exit 1; }
[[ "$COMMAND" =~ ^(init|build|test|start|validate|reset|destroy|status)$ ]] || { echo "Error: Unknown command '$COMMAND'."; exit 1; }

PROJECT_DIR="$SCRIPT_DIR/$PROJECT"
OUTPUT_DIR="$SCRIPT_DIR/output/$PROJECT"
mkdir -p "$OUTPUT_DIR"

# Compose command with project-specific file
compose() {
  docker compose -f "$PROJECT_DIR/docker-compose.yml" -p "sandbox-$PROJECT" "$@"
}

case "$COMMAND" in
  init)
    echo "=== Initializing $PROJECT sandbox ==="
    compose build
    echo "Done. Images built and cached."
    ;;

  build)
    echo "=== Building $PROJECT inside sandbox ==="
    compose run --rm -e OUTPUT_DIR=/output -v "$OUTPUT_DIR:/output" sandbox build
    ;;

  test)
    echo "=== Running $PROJECT tests inside sandbox ==="
    compose run --rm -e OUTPUT_DIR=/output -v "$OUTPUT_DIR:/output" sandbox test
    ;;

  start)
    echo "=== Starting $PROJECT services ==="
    # Start dependency services (ignore errors for services that don't exist in this composition)
    if [ "$PROJECT" = "eshop" ]; then
      compose up -d sqlserver
    elif [ "$PROJECT" = "medplum" ]; then
      compose up -d postgres redis
    fi
    # Run the sandbox container in detached mode with port mapping
    compose run -d --service-ports --name "sandbox-${PROJECT}-app" sandbox start
    echo "Services started."
    if [ "$PROJECT" = "eshop" ]; then
      echo "  → http://localhost:5106"
    elif [ "$PROJECT" = "medplum" ]; then
      echo "  → http://localhost:8103/healthcheck"
    fi
    echo "Use './sandbox.sh $PROJECT status' to check health."
    ;;

  validate)
    echo "=== Full validation of $PROJECT ==="
    compose run --rm -e OUTPUT_DIR=/output -v "$OUTPUT_DIR:/output" sandbox validate
    ;;

  reset)
    echo "=== Resetting $PROJECT sandbox ==="
    docker rm -f "sandbox-${PROJECT}-app" 2>/dev/null || true
    compose down -v
    rm -rf "$OUTPUT_DIR"/*
    echo "Containers stopped, volumes wiped. Images preserved for fast rebuild."
    ;;

  destroy)
    echo "=== Destroying $PROJECT sandbox ==="
    docker rm -f "sandbox-${PROJECT}-app" 2>/dev/null || true
    compose down -v --rmi local
    rm -rf "$OUTPUT_DIR"
    echo "Full teardown complete."
    ;;

  status)
    echo "=== $PROJECT sandbox status ==="
    compose ps
    ;;
esac
