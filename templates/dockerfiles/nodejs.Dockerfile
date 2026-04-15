# Node.js with configurable version
# Available: 22, 24 (LTS only)
# https://nodejs.org/en/about/previous-releases
ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-alpine

# Install system dependencies
RUN apk add --no-cache git curl

# Install PM2 globally
RUN npm install -g pm2

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

# Install dependencies at runtime and start with PM2
# - If no package.json or ecosystem.config.js exists, wait instead of crashing
# - If PM2 exits for any reason, keep the container alive for inspection
# - Uses npm ci for reproducible builds when lock file exists, falls back to npm install
CMD ["sh", "-c", "\
if [ ! -f package.json ]; then \
  echo 'No package.json found. Add your app files in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
if [ ! -f ecosystem.config.js ]; then \
  echo 'No ecosystem.config.js found. Add a PM2 ecosystem file in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
if [ -f package-lock.json ]; then npm ci; else npm install; fi; \
pm2-runtime start ecosystem.config.js ${PM2_APP_NAME:+--only $PM2_APP_NAME}; \
echo ''; \
echo '>>> Application exited. Container kept alive for debugging.'; \
echo '>>> Fix your code, then: docker compose restart'; \
exec tail -f /dev/null"]
