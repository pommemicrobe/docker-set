# Go with configurable version
# Available: 1.24, 1.23
# https://hub.docker.com/_/golang
ARG GO_VERSION=1.24
FROM golang:${GO_VERSION}-alpine

# Install system dependencies
RUN apk add --no-cache git curl

# Create non-root user
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || curl -f http://localhost:8080/ || exit 1

# Build and run the app at startup
# - If no go.mod exists (empty site), wait instead of crashing
# - Downloads dependencies, builds a binary, and runs it
# - Detects common Go project layouts (root main.go, cmd/server, cmd/)
# - If the app exits for any reason, keep the container alive for debugging
CMD ["sh", "-c", "\
if [ ! -f go.mod ]; then \
  echo 'No go.mod found. Add your app files in ./app/ and restart the container.'; \
  exec tail -f /dev/null; \
fi; \
go mod download; \
if [ -f main.go ] || ls *.go 2>/dev/null | head -1 | grep -q '.go'; then \
  go build -o /tmp/server . && exec /tmp/server; \
elif [ -f cmd/server/main.go ]; then \
  go build -o /tmp/server ./cmd/server && exec /tmp/server; \
elif [ -f cmd/main.go ]; then \
  go build -o /tmp/server ./cmd && exec /tmp/server; \
else \
  echo 'No Go entry point found. Create main.go or cmd/server/main.go.'; \
  exec tail -f /dev/null; \
fi; \
echo ''; \
echo '>>> Application exited. Container kept alive for debugging.'; \
echo '>>> Fix your code, then: docker compose restart'; \
exec tail -f /dev/null"]
