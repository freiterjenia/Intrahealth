# eShopOnWeb AI Agent Sandbox
# Multi-stage build optimized for layer caching
# Build context is the sandbox/ directory; source is at ../eShopOnWeb relative to it

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS base

# Install curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Copy entrypoint and shared libraries first (small, rarely changes)
COPY sandbox/eshop/run.sh /run.sh
COPY sandbox/lib/output.sh /lib/output.sh
RUN chmod +x /run.sh /lib/output.sh

WORKDIR /workspace

# Copy solution and project files first for dependency layer caching
COPY eShopOnWeb/eShopOnWeb.sln eShopOnWeb/Directory.Packages.props eShopOnWeb/global.json ./
COPY eShopOnWeb/docker-compose.dcproj ./
COPY eShopOnWeb/src/Web/Web.csproj src/Web/
COPY eShopOnWeb/src/PublicApi/PublicApi.csproj src/PublicApi/
COPY eShopOnWeb/src/ApplicationCore/ApplicationCore.csproj src/ApplicationCore/
COPY eShopOnWeb/src/Infrastructure/Infrastructure.csproj src/Infrastructure/
COPY eShopOnWeb/src/BlazorAdmin/BlazorAdmin.csproj src/BlazorAdmin/
COPY eShopOnWeb/src/BlazorShared/BlazorShared.csproj src/BlazorShared/
COPY eShopOnWeb/src/eShopWeb.AppHost/eShopWeb.AppHost.csproj src/eShopWeb.AppHost/
COPY eShopOnWeb/src/eShopWeb.AspireServiceDefaults/eShopWeb.AspireServiceDefaults.csproj src/eShopWeb.AspireServiceDefaults/
COPY eShopOnWeb/tests/UnitTests/UnitTests.csproj tests/UnitTests/
COPY eShopOnWeb/tests/IntegrationTests/IntegrationTests.csproj tests/IntegrationTests/
COPY eShopOnWeb/tests/FunctionalTests/FunctionalTests.csproj tests/FunctionalTests/
COPY eShopOnWeb/tests/PublicApiIntegrationTests/PublicApiIntegrationTests.csproj tests/PublicApiIntegrationTests/

# Restore all dependencies (this layer is cached until a csproj/props changes)
RUN dotnet restore eShopOnWeb.sln

# Copy the rest of the source code
COPY eShopOnWeb/src/ src/
COPY eShopOnWeb/tests/ tests/
COPY eShopOnWeb/CodeCoverage.runsettings ./

ENTRYPOINT ["/run.sh"]
CMD ["build"]
