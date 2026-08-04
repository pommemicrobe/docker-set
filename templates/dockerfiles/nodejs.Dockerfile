# Node.js with configurable version
# Available: 22, 24 (LTS only)
# https://nodejs.org/en/about/previous-releases
ARG NODE_VERSION=24

# =============================================================================
# base - shared ground for build and dev stages
# =============================================================================
FROM node:${NODE_VERSION}-alpine AS base

# Create non-root user
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 3000

# =============================================================================
# build - install dependencies and build the app for the prod stage
# =============================================================================
FROM base AS build

# Build context is the site directory; .dockerignore keeps secrets (.env) out
COPY app/ /app/

# A prod image without a runnable Node.js project must never ship: fail the build
RUN if [ ! -f package.json ]; then \
        echo 'ERROR: no package.json found in app/.' >&2; \
        echo 'Prod builds require a Node.js project: add package.json to app/ and rebuild.' >&2; \
        exit 1; \
    fi \
    && if [ ! -f package-lock.json ]; then \
        echo 'ERROR: no package-lock.json found in app/.' >&2; \
        echo 'Prod builds require reproducible installs (npm ci): run "npm install --package-lock-only" in app/ and rebuild.' >&2; \
        exit 1; \
    fi \
    && if ! node -e "process.exit(require('./package.json').scripts?.start ? 0 : 1)"; then \
        echo 'ERROR: no "start" script found in package.json.' >&2; \
        echo 'Prod images run "start": add scripts.start to package.json and rebuild.' >&2; \
        exit 1; \
    fi

# devDependencies included (builds need them), pruned after the build
RUN npm ci \
    && npm run build --if-present \
    && npm prune --omit=dev

# =============================================================================
# prod - minimal runtime, app + prod dependencies only (no PM2, no devtools)
# =============================================================================
FROM node:${NODE_VERSION}-alpine AS prod

# Non-root user; /app/data pre-owned so named volumes inherit ownership
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app/data \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

COPY --from=build --chown=app:app /app /app

# Expose port
EXPOSE 3000

ENV NODE_ENV=production

USER app

# Healthcheck via busybox wget (no curl in the prod image)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:3000/health || wget -qO- http://localhost:3000/ || exit 1

# Run the start script directly (verified on node:22/24-alpine):
# crash = exit = restart policy takes over
CMD ["node", "--run", "start"]

# =============================================================================
# dev - current single-stage behavior (PM2 kept for backward compat), LAST so
# untargeted builds (pre-existing sites without build.target) still get dev
# =============================================================================
FROM base AS dev

# Install system dependencies
RUN apk add --no-cache git curl

# Install PM2 globally
RUN npm install -g pm2

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || curl -f http://localhost:3000/ || exit 1

# Install dependencies at runtime and start with PM2
# - If no package.json or ecosystem config exists, wait instead of crashing
# - Accepts ecosystem.config.js or .cjs (ESM apps with "type": "module" need .cjs)
# - If PM2 exits for any reason, keep the container alive for inspection
# - Uses npm ci for reproducible builds when lock file exists, falls back to npm install
CMD ["sh", "-c", "\
if [ ! -f package.json ]; then \
  echo 'No package.json found. Add your app files in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
ECO=ecosystem.config.js; \
if [ ! -f $ECO ] && [ -f ecosystem.config.cjs ]; then ECO=ecosystem.config.cjs; fi; \
if [ ! -f $ECO ]; then \
  echo 'No ecosystem.config.js or ecosystem.config.cjs found. Add a PM2 ecosystem file in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
if [ -f package-lock.json ]; then npm ci; else npm install; fi; \
pm2-runtime start $ECO ${PM2_APP_NAME:+--only $PM2_APP_NAME}; \
echo ''; \
echo '>>> Application exited. Container kept alive for debugging.'; \
echo '>>> Fix your code, then: docker compose restart'; \
exec tail -f /dev/null"]
