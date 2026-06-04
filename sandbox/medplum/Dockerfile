# Medplum AI Agent Sandbox
# Builds the server from source using Turborepo
# Build context is the parent directory (intrahealth/); paths reference medplum/ and sandbox/

FROM node:24-slim AS base

# Install system dependencies for builds and health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    python3 \
    make \
    g++ \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install turbo globally for monorepo builds
RUN npm install -g turbo

WORKDIR /workspace

# Copy package manifests and root config files
COPY medplum/package.json medplum/package-lock.json medplum/turbo.json medplum/tsconfig.json ./
COPY medplum/api-extractor.json medplum/tsdoc.json medplum/biome.json ./

# Copy all workspace packages (packages/ + examples/) — npm ci requires complete workspace
COPY medplum/packages/ packages/
COPY medplum/examples/ examples/

# Install all dependencies (this layer is cached until package files change)
RUN npm ci

# Build server and all its workspace dependencies
RUN turbo run build --filter=@medplum/server...

# Copy entrypoint and shared libraries AFTER heavy build layers (so script changes don't trigger rebuild)
COPY sandbox/medplum/run.sh /run.sh
COPY sandbox/lib/output.sh /lib/output.sh
RUN chmod +x /run.sh /lib/output.sh

ENTRYPOINT ["/run.sh"]
CMD ["build"]
