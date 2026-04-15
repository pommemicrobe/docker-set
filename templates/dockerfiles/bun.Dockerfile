# Bun with configurable version
# Available: 1, 1.3 (tracking minor versions for patch updates)
# https://hub.docker.com/r/oven/bun
ARG BUN_VERSION=1.3
FROM oven/bun:${BUN_VERSION}-alpine

# Install system dependencies
RUN apk add --no-cache git curl

# Create non-root user
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 3000

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
