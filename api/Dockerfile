# docker-set control plane API
# Build context is api/ — built via config/api/compose.yaml

# =============================================================================
# build - compile the server; gofmt or go vet findings fail the build
# =============================================================================
FROM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod ./
COPY *.go ./

# A non-gofmt'd or non-vet-clean tree never ships
RUN test -z "$(gofmt -l .)" \
    && go vet ./... \
    && CGO_ENABLED=0 go build -ldflags="-s -w" -o /api-server .

# =============================================================================
# prod - minimal runtime plus the CLI tools the management scripts need
# =============================================================================
FROM alpine:3.23 AS prod

# bash + docker CLI + compose plugin + jq + curl: dependencies of scripts/
RUN apk add --no-cache bash docker-cli docker-cli-compose jq curl

COPY --from=build /api-server /api-server

EXPOSE 9000

# Unauthenticated liveness endpoint; port matches the LISTEN_ADDR default
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:9000/health || exit 1

# Runs as root: the Docker socket and repository writes require it
# (documented tradeoff — the container is the trust boundary, not the user)
CMD ["/api-server"]
