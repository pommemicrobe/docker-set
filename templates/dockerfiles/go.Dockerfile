# Go with configurable version
# Available: 1.26, 1.25
# https://hub.docker.com/_/golang
ARG GO_VERSION=1.26

# =============================================================================
# base - shared ground for build and dev stages
# =============================================================================
FROM golang:${GO_VERSION}-alpine AS base

# Create non-root user
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

# Expose port
EXPOSE 8080

# =============================================================================
# build - compile the app for the prod stage
# =============================================================================
FROM base AS build

# Build context is the site directory; .dockerignore keeps secrets (.env) out
COPY app/ /app/

# A prod image without a Go module must never ship: fail the build
RUN if [ ! -f go.mod ]; then \
        echo 'ERROR: no go.mod found in app/.' >&2; \
        echo 'Prod builds require a Go module: run "go mod init <module>" in app/ and rebuild.' >&2; \
        exit 1; \
    fi \
    && go mod download

# Entry point detection mirrors the dev CMD (root *.go, cmd/server, cmd)
# CGO disabled so the static binary runs on plain alpine
RUN if [ -f main.go ] || ls ./*.go >/dev/null 2>&1; then \
        target=. ; \
    elif [ -f cmd/server/main.go ]; then \
        target=./cmd/server ; \
    elif [ -f cmd/main.go ]; then \
        target=./cmd ; \
    else \
        echo 'ERROR: no Go entry point found in app/.' >&2; \
        echo 'Create main.go, cmd/server/main.go or cmd/main.go and rebuild.' >&2; \
        exit 1; \
    fi \
    && CGO_ENABLED=0 go build -ldflags="-s -w" -o /server "$target"

# =============================================================================
# prod - minimal runtime, static binary only (no toolchain, no devtools)
# =============================================================================
FROM alpine:3.23 AS prod

# Non-root user; /app/data pre-owned so named volumes inherit ownership
RUN addgroup -S app && adduser -S -G app -h /app app \
    && mkdir -p /app/data \
    && chown -R app:app /app

# Set working directory
WORKDIR /app

COPY --from=build /server /server

# Expose port
EXPOSE 8080

USER app

# Healthcheck via busybox wget (no curl in the prod image)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || wget -qO- http://localhost:8080/ || exit 1

# Run the binary directly: crash = exit = restart policy takes over
CMD ["/server"]

# =============================================================================
# dev - current single-stage behavior, kept LAST so untargeted builds
# (pre-existing sites without build.target) still produce the dev image
# =============================================================================
FROM base AS dev

# Install system dependencies
RUN apk add --no-cache git curl

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
