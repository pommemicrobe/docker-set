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
# Uses npm ci for reproducible builds when lock file exists, falls back to npm install
CMD ["sh", "-c", "if [ -f package-lock.json ]; then npm ci; else npm install; fi && pm2-runtime start ecosystem.config.js ${PM2_APP_NAME:+--only $PM2_APP_NAME}"]
