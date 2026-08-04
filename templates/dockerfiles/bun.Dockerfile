# Bun with configurable version
# Available: 1, 1.3 (tracking minor versions for patch updates)
# https://hub.docker.com/r/oven/bun
ARG BUN_VERSION=1.3

# =============================================================================
# base - shared ground for build and dev stages
# =============================================================================
FROM oven/bun:${BUN_VERSION}-alpine AS base

# Create non-root user
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 3000

# =============================================================================
# build - install and build the app for the prod stage
# =============================================================================
FROM base AS build

# Build context is the site directory; .dockerignore keeps secrets (.env) out
COPY app/ /app/

# A prod image without a runnable Bun app must never ship: fail the build
RUN if [ ! -f package.json ]; then \
        echo 'ERROR: no package.json found in app/.' >&2; \
        echo 'Prod builds require a Bun app: add package.json with a "start" script and rebuild.' >&2; \
        exit 1; \
    fi \
    && if [ ! -f bun.lock ] && [ ! -f bun.lockb ]; then \
        echo 'ERROR: no bun.lock or bun.lockb found in app/.' >&2; \
        echo 'Prod builds require a frozen lockfile: run "bun install" in app/, commit the lockfile and rebuild.' >&2; \
        exit 1; \
    fi \
    && if ! grep -q '"start"' package.json; then \
        echo 'ERROR: no "start" script found in package.json.' >&2; \
        echo 'Prod images run "bun run start": add a start script (e.g. "bun run src/index.ts") and rebuild.' >&2; \
        exit 1; \
    fi

# Full install (dev deps included) for the optional build step, then
# reinstall prod-only deps so the final node_modules ships no devtools
RUN bun install --frozen-lockfile \
    && if grep -q '"build"' package.json; then bun run build; fi \
    && rm -rf node_modules \
    && bun install --production --frozen-lockfile

# =============================================================================
# prod - runtime with prod deps only (bun is the runtime, no devtools)
# =============================================================================
FROM oven/bun:${BUN_VERSION}-alpine AS prod

# Non-root user; /app/data pre-owned so named volumes inherit ownership
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app/data \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

COPY --from=build --chown=app:app /app /app

ENV NODE_ENV=production

# Expose port
EXPOSE 3000

USER app

# Healthcheck via busybox wget (no curl in the prod image)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:3000/health || wget -qO- http://localhost:3000/ || exit 1

# Run the start script directly: crash = exit = restart policy takes over
CMD ["bun", "run", "start"]

# =============================================================================
# dev - current single-stage behavior, kept LAST so untargeted builds
# (pre-existing sites without build.target) still produce the dev image
# =============================================================================
FROM base AS dev

# Install system dependencies
RUN apk add --no-cache git curl

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || curl -f http://localhost:3000/ || exit 1

# Install dependencies at runtime and start the app
# - If no package.json exists (empty site), wait instead of crashing
# - If the app exits for any reason (error or simple script), keep the container
#   alive for inspection via `docker logs` and `docker exec`
# - Tries `bun run start`, then falls back to index.ts/index.js/main.ts/src/index.ts
CMD ["sh", "-c", "\
if [ ! -f package.json ]; then \
  echo 'No package.json found. Add your app files in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
if [ -f bun.lockb ] || [ -f bun.lock ]; then bun install --frozen-lockfile || bun install; else bun install; fi; \
if grep -q '\"start\"' package.json; then \
  bun run start; \
elif [ -f src/index.ts ]; then bun run src/index.ts; \
elif [ -f src/index.js ]; then bun run src/index.js; \
elif [ -f index.ts ]; then bun run index.ts; \
elif [ -f index.js ]; then bun run index.js; \
elif [ -f main.ts ]; then bun run main.ts; \
else \
  echo 'No start script or entry file found. Define a \"start\" script in package.json or add index.ts/index.js.'; \
  exec tail -f /dev/null; \
fi; \
echo ''; \
echo '>>> Application exited. Container kept alive for debugging.'; \
echo '>>> Fix your code, then: docker compose restart'; \
exec tail -f /dev/null"]
