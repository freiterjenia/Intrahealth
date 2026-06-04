# AI Agent Sandbox

A Docker-based sandboxed execution environment for AI coding agents. Supports building, testing, and validating two real-world projects with conflicting technology stacks.

## Quick Start

```bash
chmod +x sandbox.sh

# eShopOnWeb: init, build, and test
./sandbox.sh eshop init       # build Docker image (cached)
./sandbox.sh eshop build      # compile project inside sandbox
./sandbox.sh eshop test       # run test suite

# Medplum: init, build, and test
./sandbox.sh medplum init
./sandbox.sh medplum build
./sandbox.sh medplum test

# Full validation (build + test + start + health check)
./sandbox.sh eshop validate
./sandbox.sh medplum validate

# Start services and access in browser
./sandbox.sh eshop start      # → http://localhost:5106 (e-commerce storefront)
./sandbox.sh medplum start    # → http://localhost:8103/healthcheck (FHIR API)

# Clean up
./sandbox.sh eshop reset    # keep images, wipe state
./sandbox.sh eshop destroy  # remove everything
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    sandbox.sh (orchestrator)                  │
│              Unified CLI: init/build/test/validate/reset      │
├──────────────────────────────┬──────────────────────────────┤
│       eShop Composition      │      Medplum Composition      │
│                              │                               │
│  ┌────────────────────────┐  │  ┌─────────────────────────┐ │
│  │  sandbox (.NET 10 SDK) │  │  │  sandbox (Node 24)      │ │
│  │  - dotnet build/test   │  │  │  - turbo build          │ │
│  │  - run.sh entrypoint   │  │  │  - jest test            │ │
│  └──────────┬─────────────┘  │  └──────┬──────────────────┘ │
│             │                │         │                     │
│  ┌──────────▼─────────────┐  │  ┌──────▼───┐  ┌──────────┐ │
│  │  SQL Server 2022       │  │  │ Postgres  │  │  Redis 7 │ │
│  │  (2GB limit)           │  │  │   16      │  │          │ │
│  └────────────────────────┘  │  └──────────┘  └──────────┘ │
└──────────────────────────────┴──────────────────────────────┘
```

### Decision: Two Isolated Compositions (Not One)

**Choice:** Each project gets a completely independent docker-compose environment.

**Why:**
- AI agents work on one project at a time — no reason to co-locate SQL Server and PostgreSQL
- Isolated failure domains: a crashing .NET build can't take down Medplum's Redis
- Independent resource limits (SQL Server needs 2GB alone)
- Simpler mental model for automated consumers
- Can run both simultaneously on machines with enough RAM (~8GB), or one at a time on smaller machines

**Rejected alternative:** Single mega-composition with all services. Would waste resources, create coupling between unrelated projects, and complicate the reset/destroy lifecycle.

## Design Decisions (Deep Dives)

### 1. Clean State + Build Performance

**Problem:** An AI agent runs a build, generates code, runs tests. Then the next agent run needs a fresh environment. Starting from scratch (full image rebuild) takes 10+ minutes — unacceptable for iterative workflows.

**Solution: Three-tier caching strategy**

```
Tier 1: Base Image (SDK + system deps)          → rebuilt monthly
Tier 2: Dependency Layer (NuGet/npm packages)   → rebuilt when package files change
Tier 3: Source Code (mounted volume or COPY)    → changes every run
```

**Reset cycle:**
- `reset` = wipe source volume + DB data volumes → **seconds**
- Dependencies stay cached in the image layer → no re-download
- Only a `Dockerfile` change (new dependency) triggers a full rebuild

**eShopOnWeb specifics:**
- Copy `.csproj` + `Directory.Packages.props` first → `dotnet restore` cached as a layer
- Full source COPY after → only this layer invalidates on code changes

**Medplum specifics:**
- Copy `package.json` + `package-lock.json` for all workspace packages first → `npm ci` cached
- Source copy + `turbo build` after → turbo's own cache helps with incremental rebuilds

### 2. Non-Interactive Execution

**Problem:** AI agents can't answer prompts, click dialogs, or accept licenses interactively.

**Findings after analysis:**

| Project | Interactive Assumptions | Resolution |
|---------|----------------------|------------|
| eShopOnWeb | SQL Server EULA | `ACCEPT_EULA=Y` env var (already in compose) |
| eShopOnWeb | dev-certs trust | Only in devcontainer; not triggered in build/test |
| eShopOnWeb | NuGet restore | Non-interactive by default; `--no-restore` after initial restore |
| Medplum | npm prompts | `npm ci` is non-interactive by design |
| Medplum | Config file path | Using `env` command mode — all config via env vars |
| Medplum | DB migrations | `runMigrations: true` env var — no prompts |

**Design principle:** Every command in `run.sh` must exit with a clear exit code, no TTY required. The entrypoint scripts use `set -euo pipefail` to fail fast on any error.

### 3. Output Capture

**Problem:** An AI agent harness needs structured results — not a scrolling terminal log. It needs to know: did it pass? How long? Where are the details?

**Solution: `/output` volume with structured JSON**

Every command produces:
```json
{
  "label": "test",
  "command": "dotnet test ...",
  "exit_code": 0,
  "duration_seconds": 42,
  "stdout_file": "test_stdout.log",
  "stderr_file": "test_stderr.log",
  "timestamp": "2026-06-03T10:00:00Z"
}
```

The `validate` command produces a `summary.json` aggregating all steps:
```json
{
  "overall_exit_code": 0,
  "timestamp": "...",
  "results": [
    {"label": "build", "exit_code": 0, "duration_seconds": 15},
    {"label": "test", "exit_code": 0, "duration_seconds": 42},
    {"label": "healthcheck", "exit_code": 0, "duration_seconds": 5}
  ]
}
```

**Test framework output:**
- eShopOnWeb: `.trx` files (XML) in `/output/test-results/`
- Medplum: Jest JSON reporter output in `/output/`

An AI harness reads `summary.json` → decides pass/fail → optionally digs into logs.

## Resource Requirements

| Service | Memory Limit | CPU Limit | Notes |
|---------|-------------|-----------|-------|
| eShop sandbox (.NET SDK) | 4 GB | 2 cores | Builds large solution |
| SQL Server 2022 | 2 GB | 1 core | Microsoft minimum requirement |
| Medplum sandbox (Node) | 4 GB | 2 cores | Monorepo turbo build |
| PostgreSQL 16 | 512 MB | 0.5 cores | Lightweight for dev |
| Redis 7 | 256 MB | 0.25 cores | In-memory cache |

**Total per project:** ~6 GB (eShop) or ~5 GB (Medplum)
**Both simultaneously:** ~11 GB

## Security & Isolation

- **No `--privileged` flag** — containers run with default capabilities
- **No host network** — each composition uses its own bridge network
- **Resource limits enforced** — prevents runaway builds from exhausting host
- **No volume mounts to host system** (except `/output` for results)
- **Database passwords** are internal to the compose network — not exposed secrets
- **Read-only filesystem** consideration: not enabled by default (builds need write access), but could be added for the runtime-only `start` mode

## What Would I Improve (With More Time)

1. **Incremental source injection** — Mount a workspace volume instead of COPY, so agents can modify files without rebuilding the image
2. **BuildKit cache mounts** — `RUN --mount=type=cache,target=/root/.nuget` for NuGet/npm cache persistence across rebuilds
3. **Test parallelization** — Run eShop and Medplum tests simultaneously with resource-aware scheduling
4. **OCI image for reset** — Snapshot a "clean" state as a container checkpoint, restore instead of rebuild
5. **Network policy** — Block outbound internet from sandbox (all deps pre-baked in image)
6. **Rootless containers** — Run as non-root user for defense-in-depth
7. **Test result parsing** — Parse `.trx` / Jest JSON into a unified test result schema
8. **Timeout enforcement** — Kill runaway builds/tests after configurable deadline
9. **Secrets management** — Use Docker secrets instead of env vars for DB passwords

## AI Tool Usage Notes

This sandbox was built with AI assistance (GitHub Copilot). Key observations:

- **What worked:** Exploring both projects' existing Docker configs, understanding dependency graphs, identifying the SDK version mismatch, designing the layer caching strategy
- **What required intervention:** The Medplum Dockerfile needed manual design since the existing one uses a private base image (`dhi.io/node:24-dev`) and pre-built tarballs — neither is usable for a from-source sandbox
- **Interesting meta-observation:** I'm using an AI agent to build the environment that AI agents will run inside. The agent correctly identified that eShop tests don't need SQL Server (they use InMemory) but missed that the existing Medplum Dockerfile was unusable until prompted to investigate further.
