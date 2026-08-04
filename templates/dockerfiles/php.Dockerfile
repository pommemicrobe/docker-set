# FrankenPHP with configurable PHP version
# Available: 8.2, 8.3, 8.4, 8.5
# https://hub.docker.com/r/dunglas/frankenphp
ARG PHP_VERSION=8.5

# =============================================================================
# base - shared ground for build, prod and dev stages
# =============================================================================
FROM dunglas/frankenphp:php${PHP_VERSION}-bookworm AS base

# curl stays in base: the healthcheck needs it (bookworm ships no wget)
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN install-php-extensions \
    pdo_mysql \
    gd \
    intl \
    zip \
    opcache \
    mysqli \
    redis \
    bcmath \
    exif \
    pcntl \
    sockets \
    imagick \
    gettext

# Create non-root user
RUN useradd -r -s /bin/false -d /app app \
    && mkdir -p /app/public \
    && chown -R app:app /app

# Set working directory
WORKDIR /app/public

# =============================================================================
# build - install dependencies and build assets for the prod stage
# =============================================================================
FROM base AS build

# Build tooling (never ships in the prod image)
RUN apt-get update && apt-get install -y \
    git \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Composer (latest version)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Install Node.js (for frontend build tools)
ARG NODE_JS_VERSION=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_JS_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Build context is the site directory; .dockerignore keeps secrets (.env) out
WORKDIR /app
COPY app/ /app/

# PHP dependencies: plain PHP apps (no composer.json) build fine, but a
# broken composer install must never ship
RUN if [ -f composer.json ]; then \
        composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist \
        || { echo 'ERROR: composer install failed.' >&2; \
             echo 'Fix composer.json/composer.lock in app/ and rebuild.' >&2; \
             exit 1; }; \
    fi

# Frontend assets: only when package.json declares a build script
RUN if [ -f package.json ] \
        && node -e "process.exit((require('./package.json').scripts || {}).build ? 0 : 1)"; then \
        npm ci && npm run build; \
    fi

# =============================================================================
# prod - code baked into the image, no build tooling (no composer, no node,
# no git). No USER: FrankenPHP binds :80 and drops privileges itself
# =============================================================================
FROM base AS prod

COPY --from=build --chown=app:app /app /app

# /app/data pre-owned so named volumes inherit ownership
RUN mkdir -p /app/data && chown app:app /app/data

# Set working directory (same as dev)
WORKDIR /app/public

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# =============================================================================
# dev - current single-stage behavior, kept LAST so untargeted builds
# (pre-existing sites without build.target) still produce the dev image
# =============================================================================
FROM base AS dev

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Composer (latest version)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Install Node.js (for frontend build tools)
ARG NODE_JS_VERSION=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_JS_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
